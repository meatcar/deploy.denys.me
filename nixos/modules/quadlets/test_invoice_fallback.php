<?php
// Load the real pinned route file. Only Laravel/database collaborators are
// replaced; the fallback closure itself is the one mounted in production.
namespace Illuminate\Support\Facades {
    class Route {
        public static $fallback;
        public static function __callStatic($method, $args) {
            if ($method === 'fallback') {
                self::$fallback = $args[0];
            }
            return new class {
                public function __call($method, $args) { return $this; }
            };
        }
    }
}
namespace App\Utils {
    class Ninja {
        public static function isSelfHost() { return true; }
    }
}
namespace App\Models {
    class Account {
        public static function first() {
            return (object) ['set_react_as_default_ap' => true, 'report_errors' => false];
        }
    }
}
namespace {
    class DB {
        public static function connection() {
            return new class {
                public function getPdo() { return true; }
                public function getDatabaseName() { return 'test'; }
            };
        }
    }
    function abort($status) { throw new \RuntimeException((string) $status); }
    function request() { return $GLOBALS['request']; }
    function response() {
        return new class {
            public function view($view, $data) { return $this; }
            public function header(...$args) { return 'admin shell'; }
        };
    }
    require $argv[1];
    foreach (['billing.denys.me', 'billing-sns.denys.me', 'billing.vpn.denys.me'] as $host) {
        foreach (['/livewire/update', '/build/missing.css', '/client/missing', '/login'] as $path) {
            $GLOBALS['request'] = new class($host, $path) {
                public function __construct(public $host, public $path) {}
                public function getHost() { return $this->host; }
                public function is($pattern) { return fnmatch($pattern, ltrim($this->path, '/')); }
                public function input(...$args) { return ''; }
                public function server(...$args) { return ''; }
            };
            try {
                $result = (\Illuminate\Support\Facades\Route::$fallback)();
            } catch (\RuntimeException $e) {
                $result = $e->getMessage();
            }
            $expected = $host === 'billing.vpn.denys.me' && !str_starts_with($path, '/client/')
                ? 'admin shell' : '404';
            if ($result !== $expected) {
                throw new \RuntimeException("$host $path: expected $expected, got $result");
            }
        }
    }
    echo "Invoice Ninja public fallback denied; private fallback preserved\n";
}
