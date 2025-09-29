<?php

namespace LaravelDockerize\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;

class UpdateCommand extends Command
{
    protected $signature = 'dockerize:update {--preset=all : local|dev|prod|all} {--db= : pgsql|mysql|mariadb (optional; auto-detect if possible)} {--force : Overwrite existing files}';

    protected $description = 'Update Docker scaffolding files from the package templates (safe re-sync).';

    public function handle(): int
    {
        $fs = new Filesystem();
        $preset = strtolower((string) ($this->option('preset') ?: 'all'));
        $dbOpt = strtolower((string) ($this->option('db') ?: ''));
        $force = (bool) $this->option('force');

        $source = __DIR__ . '/../../templates';
        $target = base_path();

        // Auto-detect DB based on existing compose file contents, if not provided.
        $db = $dbOpt;
        if ($db === '') {
            $db = $this->detectDbFromCompose($target) ?? 'pgsql';
        }
        if (!in_array($db, ['pgsql', 'mysql', 'mariadb'], true)) {
            $this->warn("Unknown DB '$db'. Falling back to pgsql.");
            $db = 'pgsql';
        }

        $this->info('Updating Docker templates (preset: ' . $preset . ", db: " . $db . ')...');

        // Always copy shared docker folder
        $this->copyDirectory($fs, "$source/docker", $target . '/docker', $force);

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
            $this->warn('Unknown preset. Use one of: local, dev, prod, all. Updating all.');
            $files = array_unique(array_merge(...array_values($composeMap)));
        }

        $dbDir = "$source/compose/{$db}";
        foreach ($files as $file) {
            $from = $dbDir . '/' . $file;
            if (!$fs->exists($from)) {
                $from = "$source/compose/$file";
            }
            $this->copyFile($fs, $from, $target . '/' . $file, $force);
        }

        // Update helper files
        $this->copyFile($fs, "$source/.env.docker.example", $target . '/.env.docker.example', $force);
        $this->copyFile($fs, "$source/.dockerignore", $target . '/.dockerignore', $force);

        $this->line('');
        $this->info('Update complete. Review changes with git diff.');
        return self::SUCCESS;
    }

    protected function detectDbFromCompose(string $projectRoot): ?string
    {
        $files = [
            $projectRoot . '/docker-compose.yml',
            $projectRoot . '/docker-compose.dev.yml',
            $projectRoot . '/docker-compose.local.yml',
        ];
        foreach ($files as $f) {
            if (!is_file($f)) {
                continue;
            }
            $c = @file_get_contents($f) ?: '';
            if (stripos($c, 'image: postgres') !== false) {
                return 'pgsql';
            }
            if (stripos($c, 'image: mysql') !== false) {
                return 'mysql';
            }
            if (stripos($c, 'image: mariadb') !== false) {
                return 'mariadb';
            }
        }
        return null;
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
        $this->line("Updated: $to");
    }
}
