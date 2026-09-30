<?php

namespace App\Http\Controllers;

use App\Models\Activity;
use App\Models\Comment;
use App\Models\Todo;
use App\Models\Notification;
use Illuminate\Http\Request;

class CommentController extends Controller
{
    public function index(Request $request, Todo $todo)
    {
        $this->ensureVisible($request, $todo);

        $comments = $todo->comments()->with('user:id,name,email,role,status')->oldest()->get();

        return response()->json($comments->map(fn ($c) => $this->payload($c)));
    }

    public function store(Request $request, Todo $todo)
    {
        $this->ensureVisible($request, $todo);

        $data = $request->validate([
            'text' => ['required', 'string', 'max:5000'],
        ]);

        $comment = Comment::create([
            'todo_id' => $todo->id,
            'user_id' => $request->user()->id,
            'text' => trim($data['text']),
        ])->load('user:id,name,email,role,status');

        Activity::create([
            'user_id' => $request->user()->id,
            'action' => 'comment',
            'message' => "commented on task “{$todo->title}”",
            'metadata' => ['taskId' => $todo->id, 'projectId' => $todo->project_id],
        ]);

        if ($todo->project_id) {
            $recipients = $todo->project->members()->where('users.id', '!=', $request->user()->id)->pluck('users.id');
            foreach ($recipients as $recipientId) {
                Notification::create(['user_id' => $recipientId, 'actor_id' => $request->user()->id, 'task_id' => $todo->id, 'project_id' => $todo->project_id, 'type' => 'comment', 'title' => 'New comment', 'message' => $todo->title]);
            }
        }

        return response()->json($this->payload($comment), 201);
    }

    private function ensureVisible(Request $request, Todo $todo): void
    {
        if ($request->user()->role === 'admin') return;

        $visible = $todo->created_by === $request->user()->id
            || $todo->assignee_id === $request->user()->id
            || ($todo->project_id && $todo->project?->members()->whereKey($request->user()->id)->exists());

        abort_unless($visible, 403, 'You cannot access this task.');
    }

    private function payload(Comment $comment): array
    {
        return [
            'id' => $comment->id,
            'taskId' => $comment->todo_id,
            'userId' => $comment->user_id,
            'text' => $comment->text,
            'createdAt' => optional($comment->created_at)->toISOString(),
            'updatedAt' => optional($comment->updated_at)->toISOString(),
        ];
    }
}
