<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Notification extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id', 'type', 'title', 'message', 'read_at',
        'task_id', 'project_id', 'actor_id', 'metadata',
    ];

    protected $casts = [
        'read_at' => 'datetime',
        'metadata' => 'array',
    ];

    public function user() { return $this->belongsTo(User::class); }
    public function actor() { return $this->belongsTo(User::class, 'actor_id'); }
    public function task() { return $this->belongsTo(Todo::class, 'task_id'); }
    public function project() { return $this->belongsTo(Project::class); }
}
