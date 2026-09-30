<?php

namespace App\Http\Controllers;

use App\Models\Notification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request)
    {
        $query = Notification::where('user_id', $request->user()->id)
            ->with(['actor:id,name', 'task:id,title', 'project:id,name'])
            ->latest();

        if ($request->boolean('unread')) $query->whereNull('read_at');

        return response()->json($query->limit(min((int) $request->input('limit', 50), 100))->get()->map(fn ($n) => $this->payload($n)));
    }

    public function unreadCount(Request $request)
    {
        return response()->json(['count' => Notification::where('user_id', $request->user()->id)->whereNull('read_at')->count()]);
    }

    public function read(Request $request, Notification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 403);
        $notification->update(['read_at' => now()]);
        return response()->json($this->payload($notification->fresh(['actor:id,name', 'task:id,title', 'project:id,name'])));
    }

    public function readAll(Request $request)
    {
        Notification::where('user_id', $request->user()->id)->whereNull('read_at')->update(['read_at' => now()]);
        return response()->json(['message' => 'Notifications marked as read.']);
    }

    private function payload(Notification $n): array
    {
        return [
            'id' => $n->id,
            'type' => $n->type,
            'title' => $n->title,
            'message' => $n->message,
            'read' => $n->read_at !== null,
            'readAt' => optional($n->read_at)->toISOString(),
            'taskId' => $n->task_id,
            'projectId' => $n->project_id,
            'actor' => $n->actor ? ['id' => $n->actor->id, 'name' => $n->actor->name] : null,
            'task' => $n->task ? ['id' => $n->task->id, 'title' => $n->task->title] : null,
            'project' => $n->project ? ['id' => $n->project->id, 'name' => $n->project->name] : null,
            'metadata' => $n->metadata,
            'createdAt' => optional($n->created_at)->toISOString(),
        ];
    }
}
