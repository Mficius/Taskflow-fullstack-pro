<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Todo extends Model
{
    use HasFactory;

    protected $fillable = [
        'title', 'description', 'status', 'priority', 'due_date',
        'project_id', 'assignee_id', 'created_by', 'completed',
    ];

    protected $casts = [
        'completed' => 'boolean',
        'due_date' => 'date:Y-m-d',
    ];

    public function project() { return $this->belongsTo(Project::class); }
    public function assignee() { return $this->belongsTo(User::class, 'assignee_id'); }
    public function creator() { return $this->belongsTo(User::class, 'created_by'); }
    public function comments() { return $this->hasMany(Comment::class); }
}
