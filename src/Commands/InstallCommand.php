<?php

namespace LaravelDockerize\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;

class InstallCommand extends Command
{
    protected $signature = 'dockerize:install {--preset=all : local|dev|prod|all} {--db=pgsql : pgsql|mysql|mariadb} {--force : Overwrite existing files}';

    protected $description = 'Install Docker scaffolding for Laravel (local/dev/prod).';

    public function handle(): int
    {
        $fs = new Filesystem();
        $preset = strtolower((string) $this->option('preset')) ?: 'all';
        $db = strtolower((string) $this->option('db')) ?: 'pgsql';
        $force = (bool) $this->option('force');

        $source = __DIR__ . '/../../templates';
        $target = base_path();

        $this->info('Installing Docker templates (preset: ' . $preset . ", db: " . $db . ')...');

        // Always copy shared docker folder
        $this->copyDirectory($fs, "$source/docker", $target . '/docker', $force);

        // Compose files by preset
        $composeMap = [
            'local' => ['docker-compose.local.yml'],
            'dev'   => ['docker-compose.dev.yml'],
            'prod'  => ['docker-compose.yml'],
        ];

        if ($preset === 'all') {
            $files = array_unique(array_merge(...array_values($composeMap)));
        } elseif (isset($composeMap[$preset])) {
            $files = $composeMap[$preset];
        } else {
            $this->warn('Unknown preset. Use one of: local, dev, prod, all. Installing all.');
            $files = array_unique(array_merge(...array_values($composeMap)));
        }

        $dbDir = "$source/compose/" . ($db ?: 'pgsql');
        if (!in_array($db, ['pgsql', 'mysql', 'mariadb'], true) || !is_dir($dbDir)) {
            $this->warn('Unknown --db option. Falling back to pgsql.');
            $dbDir = "$source/compose/pgsql";
        }

        foreach ($files as $file) {
            $from = $dbDir . '/' . $file;
            // Fallback to root templates if db-specific file missing
            if (!$fs->exists($from)) {
                $from = "$source/compose/$file";
            }
            $this->copyFile($fs, $from, $target . '/' . $file, $force);
        }

        // Example env for docker
        $this->copyFile($fs, "$source/.env.docker.example", $target . '/.env.docker.example', $force);
        // .dockerignore to reduce build context and improve performance
        $this->copyFile($fs, "$source/.dockerignore", $target . '/.dockerignore', $force);

        $this->line('');
        $this->info('Done. Next steps:');
        $this->line('- Copy or merge .env.docker.example into your .env for Docker values.');
        $this->line('- docker compose -f docker-compose.local.yml up -d  (for local dev with hot reload)');
        $this->line('- docker compose -f docker-compose.dev.yml up -d    (for dev stack)');
        $this->line('- docker compose up -d                              (for production-like)');

        return self::SUCCESS;
    }

    protected function copyDirectory(Filesystem $fs, string $from, string $to, bool $force): void
    {
        if (!$fs->exists($from)) {
            return;
        }
        $fs->ensureDirectoryExists($to);
        foreach ($fs->allFiles($from) as $file) {
            $rel = ltrim(str_replace($from, '', $file->getPathname()), DIRECTORY_SEPARATOR);
            $dest = $to . DIRECTORY_SEPARATOR . $rel;
            $this->copyFile($fs, (string)$file, $dest, $force);
        }
    }

    protected function copyFile(Filesystem $fs, string $from, string $to, bool $force): void
    {
        $fs->ensureDirectoryExists(dirname($to));
        if ($fs->exists($to) && !$force) {
            $this->warn("Exists: $to (use --force to overwrite)");
            return;
        }
        $fs->copy($from, $to);
        $this->line("Created: $to");
    }
}
