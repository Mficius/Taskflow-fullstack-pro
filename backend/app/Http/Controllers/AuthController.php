<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', strtolower($credentials['email']))->first();

        if (!$user || $user->status !== 'active' || !Hash::check($credentials['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['Email ou mot de passe incorrect.'],
            ]);
        }

        $user->tokens()->delete();
        $token = $user->createToken('taskflow-web')->plainTextToken;

        return response()->json([
            'user' => $this->userPayload($user),
            'access_token' => $token,
            'token_type' => 'Bearer',
        ]);
    }

    public function me(Request $request)
    {
        return response()->json(['user' => $this->userPayload($request->user())]);
    }

    public function logout(Request $request)
    {
        $request->user()?->currentAccessToken()?->delete();
        return response()->json(['message' => 'Logged out.']);
    }

    public function profile(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email,'.$request->user()->id],
        ]);

        $user = $request->user();
        $user->update([...$data, 'email' => strtolower($data['email'])]);

        return response()->json(['user' => $this->userPayload($user->fresh())]);
    }

    public function password(Request $request)
    {
        $data = $request->validate([
            'currentPassword' => ['required', 'string'],
            'newPassword' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        if (!Hash::check($data['currentPassword'], $request->user()->password)) {
            throw ValidationException::withMessages(['currentPassword' => ['Current password is incorrect.']]);
        }

        $request->user()->update(['password' => Hash::make($data['newPassword'])]);
        $currentId = $request->user()->currentAccessToken()?->id;
        $request->user()->tokens()->where('id', '!=', $currentId)->delete();

        return response()->json(['message' => 'Password updated.']);
    }

    private function userPayload(User $user): array
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
