<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = ['name', 'email', 'password', 'role', 'status'];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function projects() { return $this->belongsToMany(Project::class)->withTimestamps(); }
    public function assignedTasks() { return $this->hasMany(Todo::class, 'assignee_id'); }
    public function createdTasks() { return $this->hasMany(Todo::class, 'created_by'); }
    public function comments() { return $this->hasMany(Comment::class); }
    public function activities() { return $this->hasMany(Activity::class); }
    public function notifications() { return $this->hasMany(Notification::class); }
    public function savedViews() { return $this->hasMany(SavedView::class); }
}
