<?php

namespace LaravelDockerize;

use Illuminate\Support\ServiceProvider as BaseServiceProvider;
use LaravelDockerize\Commands\InstallCommand;
use LaravelDockerize\Commands\UpdateCommand;

class ServiceProvider extends BaseServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->commands([
                InstallCommand::class,
                UpdateCommand::class,
            ]);
        }
    }
}
