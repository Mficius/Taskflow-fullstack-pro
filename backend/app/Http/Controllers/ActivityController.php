<?php

namespace App\Http\Controllers;

use App\Models\Activity;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class ActivityController extends Controller
{
    public function index(Request $request)
    {
        $query = $this->visibleQuery($request)->latest()->limit(min((int) $request->input('limit', 100), 200));
        if ($request->filled('action') && $request->input('action') !== 'all') $query->where('action', $request->input('action'));
        if ($request->filled('q')) {
            $term = trim($request->input('q'));
            $query->where('message', 'like', "%{$term}%");
        }
        return response()->json($query->get()->map(fn ($a) => $this->payload($a)));
    }

    public function audit(Request $request)
    {
        $query = $this->visibleQuery($request)->latest()->limit(min((int) $request->input('limit', 200), 500));
        if ($request->filled('action') && $request->input('action') !== 'all') $query->where('action', $request->input('action'));
        return response()->json($query->get()->map(fn ($a) => $this->payload($a)));
    }

    private function visibleQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Activity::with('user:id,name,email,role,status');
        if ($user->role === 'admin') return $query;
        $projectIds = $user->projects()->pluck('projects.id');
        return $query->where(function ($q) use ($user, $projectIds) {
            $q->where('user_id', $user->id);
            foreach ($projectIds as $projectId) {
                $q->orWhereJsonContains('metadata->projectId', (int) $projectId);
            }
        });
    }

    private function payload(Activity $a): array
    {
        $metadata = $a->metadata ?? [];
        return [
            'id' => $a->id, 'userId' => $a->user_id, 'action' => $a->action, 'message' => $a->message,
            'metadata' => $metadata, 'taskId' => $metadata['taskId'] ?? null, 'projectId' => $metadata['projectId'] ?? null,
            'createdAt' => optional($a->created_at)->toISOString(),
            'user' => $a->user ? ['id' => $a->user->id, 'name' => $a->user->name, 'email' => $a->user->email, 'role' => $a->user->role] : null,
        ];
    }
}
