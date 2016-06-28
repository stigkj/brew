#:  * `tap`:
#:    List all installed taps.
#:
#:  * `tap` [`--full`] <user>`/`<repo> [<URL>]:
#:    Tap a formula repository.
#:
#:    With <URL> unspecified, taps a formula repository from GitHub using HTTPS.
#:    Since so many taps are hosted on GitHub, this command is a shortcut for
#:    `tap <user>/<repo> https://github.com/<user>/homebrew-<repo>`.
#:
#:    With <URL> specified, taps a formula repository from anywhere, using
#:    any transport protocol that `git` handles. The one-argument form of `tap`
#:    simplifies but also limits. This two-argument command makes no
#:    assumptions, so taps can be cloned from places other than GitHub and
#:    using protocols other than HTTPS, e.g., SSH, GIT, HTTP, FTP(S), RSYNC.
#:
#:    By default, the repository is cloned as a shallow copy (`--depth=1`), but
#:    if `--full` is passed, a full clone will be used. To convert a shallow copy
#:    to a full copy, you can retap passing `--full` without first untapping.
#:
#:    `tap` is re-runnable and exits successfully if there's nothing to do.
#:    However, retapping with a different <URL> will cause an exception, so first
#:    `untap` if you need to modify the <URL>.
#:
#:  * `tap` `--repair`:
#:    Migrate tapped formulae from symlink-based to directory-based structure.
#:
#:  * `tap` `--list-official`:
#:    List all official taps.
#:
#:  * `tap` `--list-pinned`:
#:    List all pinned taps.

require "tap"

module Homebrew
  def tap
    if ARGV.include? "--repair"
      Tap.each(&:link_manpages)
    elsif ARGV.include? "--list-official"
      require "official_taps"
      puts OFFICIAL_TAPS.map { |t| "homebrew/#{t}" }
    elsif ARGV.include? "--list-pinned"
      puts Tap.select(&:pinned?).map(&:name)
    elsif ARGV.named.empty?
      puts Tap.names
    else
      tap = Tap.fetch(ARGV.named[0])
      begin
        tap.install :clone_target => ARGV.named[1],
                    :full_clone   => full_clone?,
                    :quiet        => ARGV.quieter?
      rescue TapRemoteMismatchError => e
        odie e
      rescue TapAlreadyTappedError, TapAlreadyUnshallowError
        # Do nothing.
      end
    end
  end

  def full_clone?
    ARGV.include?("--full") || ARGV.homebrew_developer?
  end

  # @deprecated this method will be removed in the future, if no external commands use it.
  def install_tap(user, repo, clone_target = nil)
    opoo "Homebrew.install_tap is deprecated, use Tap#install."
    tap = Tap.fetch(user, repo)
    begin
      tap.install(:clone_target => clone_target, :full_clone => full_clone?)
    rescue TapAlreadyTappedError
      false
    else
      true
    end
  end
  def install_tap_my_version(user, repo, clone_target = nil)
    # ensure git is installed
    Utils.ensure_git_installed!

    tap = Tap.fetch user, repo
    return false if tap.installed?
    ohai "Tapping #{tap}"

    original_remote = clone_target || "https://github.com/#{tap.user}/homebrew-#{tap.repo}"
    my_remote = "git@github.com:stigkj/homebrew-#{tap.user}-#{tap.repo}"

    args = %W[clone #{my_remote} #{tap.path}]
    args << "--depth=1" unless ARGV.include?("--full")

    begin
      if system "git", *args
        safe_system "git", "--git-dir=#{tap.path}/.git", "remote", "add", "upstream", original_remote
      else
        args[1] = original_remote
        safe_system "git", *args
      end
    rescue Interrupt, ErrorDuringExecution
      ignore_interrupts do
        sleep 0.1 # wait for git to cleanup the top directory when interrupt happens.
        tap.path.parent.rmdir_if_possible
      end
      raise
    end

    formula_count = tap.formula_files.size
    puts "Tapped #{formula_count} formula#{plural(formula_count, "e")} (#{tap.path.abv})"
    Descriptions.cache_formulae(tap.formula_names)

    if !clone_target && tap.private?
      puts <<-EOS.undent
        It looks like you tapped a private repository. To avoid entering your
        credentials each time you update, you can use git HTTP credential
        caching or issue the following command:

          cd #{tap.path}
          git remote set-url origin git@github.com:#{tap.user}/homebrew-#{tap.repo}.git
      EOS
    end

    true
  end

end
