# Render's default Ruby build runs `rake assets:precompile` without `npm ci`.
# Flowbite is imported from node_modules during tailwindcss:build.
namespace :render do
  desc "Install npm packages for Tailwind/Flowbite (used on Render and similar hosts)"
  task :install_npm_packages do
    lockfile = Rails.root.join("package-lock.json")
    next unless lockfile.exist?

    unless system("command -v npm >/dev/null")
      abort "npm is required to build assets (Flowbite/Tailwind). Install Node on the host or use ./bin/render-build."
    end

    system("npm ci") || abort("npm ci failed")
  end
end
