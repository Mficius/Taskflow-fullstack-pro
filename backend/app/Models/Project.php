<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Project extends Model
{
    use HasFactory;

    protected $fillable = ['name', 'description', 'created_by'];

    public function members()
    {
        return $this->belongsToMany(User::class)->withTimestamps();
    }

    public function tasks()
    {
        return $this->hasMany(Todo::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
