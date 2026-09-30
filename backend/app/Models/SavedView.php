<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SavedView extends Model
{
    use HasFactory;

    protected $fillable = ['user_id', 'name', 'resource', 'filters'];
    protected $casts = ['filters' => 'array'];

    public function user() { return $this->belongsTo(User::class); }
}
