<?php

namespace App\Http\Controllers;

use App\Models\Project;
use App\Models\Todo;
use Carbon\Carbon;
use Illuminate\Http\Request;

class AnalyticsController extends Controller
{
    public function index(Request $request)
    {
        $days = max(7, min((int) $request->input('days', 30), 90));
        $projectId = $request->input('projectId');
        $user = $request->user();
        $query = Todo::query()->with('project:id,name');
        if ($user->role !== 'admin') $query->where(fn ($q) => $q->where('created_by', $user->id)->orWhere('assignee_id', $user->id)->orWhereHas('project.members', fn ($m) => $m->whereKey($user->id)));
        if ($projectId) $query->where('project_id', $projectId);
        $from = today()->subDays($days - 1);
        $query->where(function ($q) use ($from) {
            $q->whereDate('created_at', '>=', $from)
              ->orWhereDate('updated_at', '>=', $from);
        });
        $tasks = $query->get();
        $done = $tasks->where('status', 'done')->count();
        $overdue = $tasks->filter(fn ($t) => $t->status !== 'done' && $t->due_date && Carbon::parse($t->due_date)->isBefore(today()))->count();
        $projects = Project::query();
        if ($user->role !== 'admin') $projects->whereHas('members', fn ($q) => $q->whereKey($user->id));
        $projectStats = $projects->withCount(['tasks', 'tasks as completed_tasks_count' => fn ($q) => $q->where('status', 'done')])->get()->map(fn ($p) => ['id' => $p->id, 'name' => $p->name, 'total' => $p->tasks_count, 'completed' => $p->completed_tasks_count, 'progress' => $p->tasks_count ? round($p->completed_tasks_count / $p->tasks_count * 100) : 0])->values();
        return response()->json(['periodDays' => $days, 'projectId' => $projectId ? (int) $projectId : null, 'summary' => ['total' => $tasks->count(), 'completed' => $done, 'active' => $tasks->count() - $done, 'overdue' => $overdue, 'completionRate' => $tasks->count() ? round($done / $tasks->count() * 100) : 0], 'status' => ['todo' => $tasks->where('status', 'todo')->count(), 'inProgress' => $tasks->where('status', 'in_progress')->count(), 'done' => $done], 'priority' => ['low' => $tasks->where('priority', 'low')->count(), 'medium' => $tasks->where('priority', 'medium')->count(), 'high' => $tasks->where('priority', 'high')->count()], 'projects' => $projectStats]);
    }
}
