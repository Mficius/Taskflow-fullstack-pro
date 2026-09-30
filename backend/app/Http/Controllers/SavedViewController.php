<?php

namespace App\Http\Controllers;

use App\Models\SavedView;
use Illuminate\Http\Request;

class SavedViewController extends Controller
{
    public function index(Request $request)
    {
        $resource = $request->input('resource');
        $query = SavedView::where('user_id', $request->user()->id)->latest();
        if ($resource) $query->where('resource', $resource);
        return response()->json($query->get()->map(fn ($v) => $this->payload($v)));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'resource' => ['required', 'string', 'max:50'],
            'filters' => ['required', 'array'],
        ]);
        $view = SavedView::create([...$data, 'user_id' => $request->user()->id]);
        return response()->json($this->payload($view), 201);
    }

    public function update(Request $request, SavedView $savedView)
    {
        abort_unless($savedView->user_id === $request->user()->id, 403);
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'filters' => ['sometimes', 'required', 'array'],
        ]);
        $savedView->update($data);
        return response()->json($this->payload($savedView->fresh()));
    }

    public function destroy(Request $request, SavedView $savedView)
    {
        abort_unless($savedView->user_id === $request->user()->id, 403);
        $savedView->delete();
        return response()->json(['message' => 'Saved view deleted.']);
    }

    private function payload(SavedView $v): array
    {
        return ['id' => $v->id, 'name' => $v->name, 'resource' => $v->resource, 'filters' => $v->filters, 'createdAt' => optional($v->created_at)->toISOString(), 'updatedAt' => optional($v->updated_at)->toISOString()];
    }
}
