<?php

namespace App\Http\Controllers;

use App\Models\Activity;
use App\Models\Project;
use App\Models\Todo;
use App\Models\Notification;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class TodoController extends Controller
{
    public function index(Request $request)
    {
        $query = Todo::with(['project:id,name', 'assignee:id,name,email,role,status'])
            ->latest();

        $this->scopeForUser($query, $request->user());
        if ($request->filled('projectId')) $query->where('project_id', $request->integer('projectId'));
        if ($request->filled('status') && $request->input('status') !== 'all') $query->where('status', $request->input('status'));
        if ($request->filled('priority') && $request->input('priority') !== 'all') $query->where('priority', $request->input('priority'));
        if ($request->filled('assigneeId')) $query->where('assignee_id', $request->input('assigneeId'));
        if ($request->filled('q')) { $term = trim($request->input('q')); $query->where(fn ($q) => $q->where('title', 'like', "%{$term}%")->orWhere('description', 'like', "%{$term}%")); }
        if ($request->input('due') === 'overdue') $query->where('status', '!=', 'done')->whereDate('due_date', '<', today());
        if ($request->input('due') === 'today') $query->whereDate('due_date', today());
        if ($request->input('due') === 'upcoming') $query->whereBetween('due_date', [today(), today()->addDays(7)]);
        if ($request->input('due') === 'none') $query->whereNull('due_date');

        return response()->json($query->get()->map(fn ($t) => $this->payload($t)));
    }

    public function store(Request $request)
    {
        $data = $this->validateTask($request);
        $project = $this->projectForUser($request, $data['projectId'] ?? null);

        if (!empty($data['assigneeId'])) {
            abort_unless($project->members()->whereKey($data['assigneeId'])->exists(), 422, 'Assignee must belong to the project.');
            abort_unless(\App\Models\User::whereKey($data['assigneeId'])->where('status', 'active')->exists(), 422, 'Assignee is disabled.');
        }

        $task = Todo::create([
            'title' => $data['title'],
            'description' => $data['description'] ?? null,
            'status' => $data['status'] ?? 'todo',
            'priority' => $data['priority'] ?? 'medium',
            'due_date' => $data['dueDate'] ?? null,
            'project_id' => $project->id,
            'assignee_id' => $data['assigneeId'] ?? null,
            'created_by' => $request->user()->id,
            'completed' => ($data['status'] ?? 'todo') === 'done',
        ]);

        $task->load(['project:id,name', 'assignee:id,name,email,role,status']);
        $this->activity($request, 'create', "created task “{$task->title}”", $task->id, $task->project_id);
        if ($task->assignee_id && $task->assignee_id !== $request->user()->id) {
            Notification::create(['user_id' => $task->assignee_id, 'actor_id' => $request->user()->id, 'task_id' => $task->id, 'project_id' => $task->project_id, 'type' => 'task_assigned', 'title' => 'Task assigned to you', 'message' => $task->title]);
        }

        return response()->json($this->payload($task), 201);
    }

    public function show(Request $request, Todo $todo)
    {
        $this->ensureTaskVisible($request, $todo);
        return response()->json($this->payload($todo->load(['project:id,name', 'assignee:id,name,email,role,status'])));
    }

    public function update(Request $request, Todo $todo)
    {
        $this->ensureTaskVisible($request, $todo);

        $data = $this->validateTask($request, true);
        $oldAssignee = $todo->assignee_id;
        $action = array_key_exists('status', $data) && $data['status'] !== $todo->status ? 'move'
            : (array_key_exists('assigneeId', $data) && (string) ($data['assigneeId'] ?? '') !== (string) ($todo->assignee_id ?? '') ? 'assign' : 'update');
        if (isset($data['projectId'])) {
            $project = $this->projectForUser($request, $data['projectId']);
        } else {
            $project = $todo->project;
        }

        if (array_key_exists('assigneeId', $data) && $data['assigneeId']) {
            abort_unless($project && $project->members()->whereKey($data['assigneeId'])->exists(), 422, 'Assignee must belong to the project.');
        }

        $updates = [];
        foreach (['title', 'description', 'status', 'priority'] as $key) {
            if (array_key_exists($key, $data)) $updates[$key] = $data[$key];
        }
        if (array_key_exists('dueDate', $data)) $updates['due_date'] = $data['dueDate'];
        if (array_key_exists('projectId', $data)) $updates['project_id'] = $data['projectId'];
        if (array_key_exists('assigneeId', $data)) $updates['assignee_id'] = $data['assigneeId'] ?: null;
        if (array_key_exists('completed', $data)) $updates['completed'] = (bool) $data['completed'];
        if (array_key_exists('status', $data)) $updates['completed'] = $data['status'] === 'done';
        $todo->update($updates);

        $todo->load(['project:id,name', 'assignee:id,name,email,role,status']);
        $this->activity($request, $action, "{$action} task “{$todo->title}”", $todo->id, $todo->project_id);
        if ($action === 'assign' && $todo->assignee_id && $todo->assignee_id !== $oldAssignee && $todo->assignee_id !== $request->user()->id) {
            Notification::create(['user_id' => $todo->assignee_id, 'actor_id' => $request->user()->id, 'task_id' => $todo->id, 'project_id' => $todo->project_id, 'type' => 'task_assigned', 'title' => 'Task assigned to you', 'message' => $todo->title]);
        }

        return response()->json($this->payload($todo));
    }

    public function destroy(Request $request, Todo $todo)
    {
        $this->ensureTaskVisible($request, $todo);
        $title = $todo->title;
        $todo->delete();
        $this->activity($request, 'delete', "deleted task “{$title}”");

        return response()->json(['message' => 'Todo deleted']);
    }

    private function validateTask(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'title' => [$required, 'string', 'max:255'],
            'description' => ['sometimes', 'nullable', 'string', 'max:10000'],
            'status' => ['sometimes', Rule::in(['todo', 'in_progress', 'done'])],
            'priority' => ['sometimes', Rule::in(['low', 'medium', 'high'])],
            'dueDate' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'projectId' => [$required, 'integer', 'exists:projects,id'],
            'assigneeId' => ['sometimes', 'nullable', 'integer', 'exists:users,id'],
            'completed' => ['sometimes', 'boolean'],
        ]);
    }

    private function projectForUser(Request $request, $projectId): Project
    {
        abort_if(!$projectId, 422, 'A project is required.');

        $project = Project::findOrFail($projectId);
        $user = $request->user();

        if ($user->role === 'admin') return $project;

        abort_unless($project->members()->whereKey($user->id)->exists(), 403, 'You are not a member of this project.');
        return $project;
    }

    private function scopeForUser($query, $user): void
    {
        if ($user->role === 'admin') return;

        $query->where(function ($q) use ($user) {
            $q->where('created_by', $user->id)
              ->orWhere('assignee_id', $user->id)
              ->orWhereHas('project.members', fn ($m) => $m->whereKey($user->id));
        });
    }

    private function ensureTaskVisible(Request $request, Todo $todo): void
    {
        if ($request->user()->role === 'admin') return;

        $visible = $todo->created_by === $request->user()->id
            || $todo->assignee_id === $request->user()->id
            || ($todo->project_id && $todo->project?->members()->whereKey($request->user()->id)->exists());

        abort_unless($visible, 403, 'You cannot access this task.');
    }

    private function payload(Todo $todo): array
    {
        return [
            'id' => $todo->id,
            'title' => $todo->title,
            'description' => $todo->description,
            'completed' => (bool) $todo->completed,
            'status' => $todo->status ?: ($todo->completed ? 'done' : 'todo'),
            'priority' => $todo->priority ?: 'medium',
            'dueDate' => optional($todo->due_date)->format('Y-m-d'),
            'projectId' => $todo->project_id,
            'assigneeId' => $todo->assignee_id,
            'createdBy' => $todo->created_by,
            'createdAt' => optional($todo->created_at)->toISOString(),
            'updatedAt' => optional($todo->updated_at)->toISOString(),
        ];
    }

    private function activity(Request $request, string $action, string $message, $todoId = null, $projectId = null): void
    {
        Activity::create([
            'user_id' => $request->user()->id,
            'action' => $action,
            'message' => $message,
            'metadata' => array_filter(['taskId' => $todoId, 'projectId' => $projectId], fn ($v) => $v !== null),
        ]);
    }
}
