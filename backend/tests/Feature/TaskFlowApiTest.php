<?php

namespace Tests\Feature;

use App\Models\Project;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TaskFlowApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_returns_sanctum_token_and_user(): void
    {
        User::factory()->create([
            'name' => 'Admin',
            'email' => 'admin@example.com',
            'password' => 'password123',
            'role' => 'admin',
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => 'admin@example.com',
            'password' => 'password123',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['user' => ['id', 'name', 'email', 'role', 'status'], 'access_token', 'token_type'])
            ->assertJsonPath('user.role', 'admin');
    }

    public function test_user_can_update_profile_and_password(): void
    {
        $user = User::factory()->create(['email' => 'profile@example.com', 'password' => 'oldpassword']);
        Sanctum::actingAs($user);

        $this->putJson('/api/auth/profile', [
            'name' => 'Updated Name',
            'email' => 'updated@example.com',
        ])->assertOk()->assertJsonPath('user.email', 'updated@example.com');

        $this->putJson('/api/auth/password', [
            'currentPassword' => 'oldpassword',
            'newPassword' => 'newpassword123',
            'newPassword_confirmation' => 'newpassword123',
        ])->assertOk();
    }

    public function test_disabled_user_cannot_login(): void
    {
        User::factory()->create([
            'email' => 'disabled@example.com',
            'password' => 'password123',
            'status' => 'disabled',
        ]);

        $this->postJson('/api/auth/login', [
            'email' => 'disabled@example.com',
            'password' => 'password123',
        ])->assertUnprocessable();
    }

    public function test_admin_can_manage_users(): void
    {
        $admin = User::factory()->create(['role' => 'admin']);
        Sanctum::actingAs($admin);

        $created = $this->postJson('/api/users', [
            'name' => 'New User',
            'email' => 'new@example.com',
            'password' => 'password123',
            'role' => 'member',
        ])->assertCreated()->json();

        $this->assertDatabaseHas('users', ['email' => 'new@example.com', 'role' => 'member']);

        $this->putJson("/api/users/{$created['id']}", ['role' => 'manager'])
            ->assertOk()
            ->assertJsonPath('role', 'manager');

        $this->deleteJson("/api/users/{$created['id']}")->assertOk();
        $this->assertDatabaseMissing('users', ['id' => $created['id']]);
    }

    public function test_member_cannot_manage_users_but_can_list_users(): void
    {
        $member = User::factory()->create(['role' => 'member']);
        Sanctum::actingAs($member);

        $this->getJson('/api/users')->assertOk();
        $this->postJson('/api/users', [
            'name' => 'Nope', 'email' => 'nope@example.com',
            'password' => 'password123', 'role' => 'member',
        ])->assertForbidden();
    }

    public function test_project_members_and_comments_are_persisted(): void
    {
        $admin = User::factory()->create(['role' => 'admin']);
        $member = User::factory()->create(['role' => 'member']);
        Sanctum::actingAs($admin);

        $project = $this->postJson('/api/projects', [
            'name' => 'DevOps Lab',
            'description' => 'Training project',
        ])->assertCreated()->json();

        $this->postJson("/api/projects/{$project['id']}/members", [
            'userId' => $member->id,
        ])->assertOk()->assertJsonFragment(['memberIds' => [$admin->id, $member->id]]);

        $task = $this->postJson('/api/todos', [
            'title' => 'Review pipeline',
            'projectId' => $project['id'],
        ])->assertCreated()->json();

        $this->postJson("/api/todos/{$task['id']}/comments", ['text' => 'Looks good.'])
            ->assertCreated()
            ->assertJsonPath('text', 'Looks good.');

        $this->getJson("/api/todos/{$task['id']}/comments")
            ->assertOk()
            ->assertJsonCount(1);

        $this->getJson('/api/activity')
            ->assertOk()
            ->assertJsonCount(4);
    }
}
