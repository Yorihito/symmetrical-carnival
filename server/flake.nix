{
  description = "AVR Controller — report proxy (Cloudflare Worker) dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          # nixpkgs' `wrangler` can fail to build from source, so we ship only
          # node and run the CLI via `npx wrangler` (fetched from npm at first use).
          packages = [
            pkgs.nodejs_22   # node / npm / npx
          ];

          shellHook = ''
            echo "report-proxy dev shell: node $(node -v) — use 'npx wrangler ...'"
          '';
        };
      });
}
