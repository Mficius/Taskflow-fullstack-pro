<?php

namespace App\Http\Controllers;

use App\Models\Project;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Http\Request;

class SearchController extends Controller
{
    public function index(Request $request)
    {
        $q = trim((string) $request->input('q', ''));
        if ($q === '' || mb_strlen($q) < 2) return response()->json(['tasks' => [], 'projects' => [], 'users' => []]);

        $user = $request->user();
        $tasks = Todo::query()->with('project:id,name')->where(function ($query) use ($q) {
            $query->where('title', 'like', "%{$q}%")->orWhere('description', 'like', "%{$q}%");
        });
        $this->scopeTasks($tasks, $user);

        $projects = Project::query()->where(function ($query) use ($q) {
            $query->where('name', 'like', "%{$q}%")->orWhere('description', 'like', "%{$q}%");
        });
        if ($user->role !== 'admin') $projects->whereHas('members', fn ($m) => $m->whereKey($user->id));

        $users = User::query()->where('status', 'active')->where(function ($query) use ($q) {
            $query->where('name', 'like', "%{$q}%")->orWhere('email', 'like', "%{$q}%");
        })->limit(10)->get();

        return response()->json([
            'tasks' => $tasks->latest()->limit(15)->get()->map(fn ($t) => ['id' => $t->id, 'title' => $t->title, 'status' => $t->status, 'projectId' => $t->project_id, 'projectName' => $t->project?->name]),
            'projects' => $projects->latest()->limit(10)->get()->map(fn ($p) => ['id' => $p->id, 'name' => $p->name, 'description' => $p->description]),
            'users' => $users->map(fn ($u) => ['id' => $u->id, 'name' => $u->name, 'email' => $u->email, 'role' => $u->role]),
        ]);
    }

    private function scopeTasks($query, $user): void
    {
        if ($user->role === 'admin') return;
        $query->where(fn ($q) => $q->where('created_by', $user->id)->orWhere('assignee_id', $user->id)->orWhereHas('project.members', fn ($m) => $m->whereKey($user->id)));
    }
}
