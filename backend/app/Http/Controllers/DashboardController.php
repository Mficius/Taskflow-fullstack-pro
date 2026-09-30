<?php

namespace App\Http\Controllers;

use App\Models\Project;
use App\Models\Todo;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function index(Request $request)
    {
        $days = max(7, min((int) $request->input('days', 30), 90));
        $user = $request->user();
        $tasks = Todo::query()->with('project:id,name');
        $this->scopeTasks($tasks, $user);
        $all = $tasks->get();
        $done = $all->where('status', 'done')->count();
        $active = $all->where('status', '!=', 'done')->count();
        $overdue = $all->filter(fn ($t) => $t->status !== 'done' && $t->due_date && Carbon::parse($t->due_date)->isBefore(today()))->count();
        $from = today()->subDays($days - 1);
        $recent = $all->filter(fn ($t) => $t->updated_at && $t->updated_at->greaterThanOrEqualTo($from));
        $projects = Project::query();
        if ($user->role !== 'admin') $projects->whereHas('members', fn ($q) => $q->whereKey($user->id));
        $projectRows = $projects->withCount(['tasks', 'tasks as completed_tasks_count' => fn ($q) => $q->where('status', 'done')])->latest()->limit(8)->get()->map(fn ($p) => ['id' => $p->id, 'name' => $p->name, 'total' => $p->tasks_count, 'completed' => $p->completed_tasks_count, 'progress' => $p->tasks_count ? round($p->completed_tasks_count / $p->tasks_count * 100) : 0]);

        return response()->json([
            'periodDays' => $days,
            'kpis' => ['totalTasks' => $all->count(), 'completed' => $done, 'active' => $active, 'overdue' => $overdue, 'completionRate' => $all->count() ? round($done / $all->count() * 100) : 0, 'recentChanges' => $recent->count()],
            'statusDistribution' => ['todo' => $all->where('status', 'todo')->count(), 'inProgress' => $all->where('status', 'in_progress')->count(), 'done' => $done],
            'priorityDistribution' => ['low' => $all->where('priority', 'low')->count(), 'medium' => $all->where('priority', 'medium')->count(), 'high' => $all->where('priority', 'high')->count()],
            'projects' => $projectRows,
            'upcoming' => $all->where('status', '!=', 'done')->filter(fn ($t) => $t->due_date && Carbon::parse($t->due_date)->between(today(), today()->addDays(14)))->sortBy('due_date')->take(8)->map(fn ($t) => ['id' => $t->id, 'title' => $t->title, 'dueDate' => optional($t->due_date)->format('Y-m-d'), 'projectId' => $t->project_id, 'projectName' => $t->project?->name])->values(),
            'people' => $user->role === 'admin' ? User::where('status', 'active')->count() : User::where('status', 'active')->whereHas('projects', fn ($q) => $q->whereHas('members', fn ($m) => $m->whereKey($user->id)))->count(),
        ]);
    }

    private function scopeTasks($query, $user): void
    {
        if ($user->role === 'admin') return;
        $query->where(fn ($q) => $q->where('created_by', $user->id)->orWhere('assignee_id', $user->id)->orWhereHas('project.members', fn ($m) => $m->whereKey($user->id)));
    }
}
