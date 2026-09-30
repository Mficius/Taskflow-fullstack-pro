<?php

namespace App\Http\Controllers;

use App\Models\Activity;
use App\Models\Project;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Models\Notification;

class ProjectController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $query = Project::with('members:id,name,email,role,status')->latest();

        if (!in_array($user->role, ['admin', 'manager'], true)) {
            $query->whereHas('members', fn ($q) => $q->whereKey($user->id));
        } elseif ($user->role === 'manager') {
            $query->where(function ($q) use ($user) {
                $q->where('created_by', $user->id)
                  ->orWhereHas('members', fn ($m) => $m->whereKey($user->id));
            });
        }

        return response()->json($query->get()->map(fn ($p) => $this->payload($p)));
    }

    public function show(Request $request, Project $project)
    {
        $this->ensureVisible($request, $project);
        $project->load(['members:id,name,email,role,status', 'tasks:id,title,status,priority,due_date,project_id,assignee_id,created_by,completed,created_at,updated_at']);
        return response()->json($this->payload($project, true));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:5000'],
        ]);

        $project = DB::transaction(function () use ($data, $request) {
            $p = Project::create([...$data, 'created_by' => $request->user()->id]);
            $p->members()->attach($request->user()->id);
            return $p->load('members:id,name,email,role,status');
        });

        $this->activity($request, 'create', "created project “{$project->name}”", $project->id);

        return response()->json($this->payload($project), 201);
    }

    public function update(Request $request, Project $project)
    {
        $this->ensureCanManage($request, $project);

        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:5000'],
        ]);
        $project->update($data);

        $this->activity($request, 'update', "updated project “{$project->name}”", $project->id);

        return response()->json($this->payload($project->fresh('members:id,name,email,role,status')));
    }

    public function destroy(Request $request, Project $project)
    {
        $this->ensureCanManage($request, $project);
        $name = $project->name;
        $project->delete();

        $this->activity($request, 'delete', "deleted project “{$name}”");

        return response()->json(['message' => 'Project deleted.']);
    }

    public function addMember(Request $request, Project $project)
    {
        $this->ensureCanManage($request, $project);
        $data = $request->validate(['userId' => ['required', 'integer', 'exists:users,id']]);
        $memberUser = \App\Models\User::findOrFail($data['userId']);
        abort_if($memberUser->status !== 'active', 422, 'Disabled users cannot be added to a project.');
        $project->members()->syncWithoutDetaching([$data['userId']]);
        $project->load('members:id,name,email,role,status');

        $member = $project->members->firstWhere('id', $data['userId']);
        $this->activity($request, 'update', "added {$member->name} to project “{$project->name}”", $project->id);
        Notification::create(['user_id' => $member->id, 'actor_id' => $request->user()->id, 'project_id' => $project->id, 'type' => 'project_member', 'title' => 'Added to project', 'message' => $project->name]);

        return response()->json($this->payload($project));
    }

    public function removeMember(Request $request, Project $project, int $userId)
    {
        $this->ensureCanManage($request, $project);
        abort_if($project->created_by === $userId, 422, 'The project creator cannot be removed.');

        $project->members()->detach($userId);
        $this->activity($request, 'update', "removed a member from project “{$project->name}”", $project->id);

        return response()->json($this->payload($project->fresh('members:id,name,email,role,status')));
    }

    private function ensureVisible(Request $request, Project $project): void
    {
        $user = $request->user();
        if ($user->role === 'admin') return;
        abort_unless($project->members()->whereKey($user->id)->exists(), 403, 'You cannot access this project.');
    }

    private function ensureCanManage(Request $request, Project $project): void
    {
        $user = $request->user();
        if ($user->role === 'admin') return;

        abort_unless(
            $user->role === 'manager' &&
            ($project->created_by === $user->id || $project->members()->whereKey($user->id)->exists()),
            403,
            'You cannot manage this project.'
        );
    }

    private function payload(Project $project, bool $detail = false): array
    {
        return [
            'id' => $project->id,
            'name' => $project->name,
            'description' => $project->description,
            'memberIds' => $project->members->pluck('id')->values()->all(),
            'createdBy' => $project->created_by,
            'createdAt' => optional($project->created_at)->toISOString(),
            'updatedAt' => optional($project->updated_at)->toISOString(),
            'members' => $project->relationLoaded('members') ? $project->members->map(fn ($u) => ['id' => $u->id, 'name' => $u->name, 'email' => $u->email, 'role' => $u->role, 'status' => $u->status])->values()->all() : [],
            'tasks' => $detail && $project->relationLoaded('tasks') ? $project->tasks->map(fn ($t) => [
                'id' => $t->id, 'title' => $t->title, 'status' => $t->status, 'priority' => $t->priority, 'dueDate' => optional($t->due_date)->format('Y-m-d'), 'projectId' => $t->project_id, 'assigneeId' => $t->assignee_id, 'createdBy' => $t->created_by, 'completed' => (bool) $t->completed, 'createdAt' => optional($t->created_at)->toISOString(), 'updatedAt' => optional($t->updated_at)->toISOString()
            ])->values()->all() : [],
        ];
    }

    private function activity(Request $request, string $action, string $message, $projectId = null): void
    {
        Activity::create([
            'user_id' => $request->user()->id,
            'action' => $action,
            'message' => $message,
            'metadata' => $projectId ? ['projectId' => $projectId] : null,
        ]);
    }
}
