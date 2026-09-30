<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Comment extends Model
{
    use HasFactory;

    protected $fillable = ['todo_id', 'user_id', 'text'];

    protected $casts = ['created_at' => 'datetime', 'updated_at' => 'datetime'];

    public function todo() { return $this->belongsTo(Todo::class); }
    public function user() { return $this->belongsTo(User::class); }
}
