<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Support\Facades\Hash;

class UserController extends Controller
{
    public function index()
    {
        return response()->json(
            User::query()->orderBy('name')->get()->map(fn ($u) => $this->payload($u))
        );
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
            'role' => ['required', Rule::in(['admin', 'manager', 'member'])],
        ]);

        $user = User::create([
            ...$data,
            'email' => strtolower($data['email']),
            'status' => 'active',
        ]);

        return response()->json($this->payload($user), 201);
    }

    public function update(Request $request, User $user)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:120'],
            'email' => ['sometimes', 'required', 'email', 'max:255', Rule::unique('users')->ignore($user->id)],
            'password' => ['sometimes', 'nullable', 'string', 'min:8'],
            'role' => ['sometimes', Rule::in(['admin', 'manager', 'member'])],
            'status' => ['sometimes', Rule::in(['active', 'disabled'])],
        ]);

        if (array_key_exists('password', $data)) {
            if ($data['password']) $data['password'] = Hash::make($data['password']);
            else unset($data['password']);
        }
        if (isset($data['email'])) $data['email'] = strtolower($data['email']);

        $user->update($data);

        if ($user->status === 'disabled' || $user->role !== ($request->user()->role ?? $user->role)) {
            // Role changes are intentionally kept server-side; the current user's token remains valid
            // until logout, while disabled users are blocked at login and by the middleware below.
        }

        return response()->json($this->payload($user->fresh()));
    }

    public function destroy(Request $request, User $user)
    {
        abort_if($request->user()->is($user), 422, 'You cannot delete your own account.');
        $user->delete();

        return response()->json(['message' => 'User deleted.']);
    }

    private function payload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'role' => $user->role,
            'status' => $user->status,
        ];
    }
}
