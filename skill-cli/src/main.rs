use anyhow::{Context, Result, bail};
use cc_switch_lib::{
    AppType, Database, ImportSkillSelection, InstalledSkill, SkillApps, SkillService,
};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::process::ExitCode;
use std::str::FromStr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Parser, Debug)]
#[command(
    name = "skill-cli",
    version,
    about = "Popskill sidecar for CC Switch skills"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Return sidecar and local CC Switch diagnostics.
    Health {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Return saved CC Switch WebDAV sync settings with secrets removed.
    WebdavStatus {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Save CC Switch WebDAV sync settings. Passwords are accepted through an env var only.
    WebdavConfigure {
        #[arg(long)]
        base_url: String,
        #[arg(long)]
        username: String,
        #[arg(long)]
        password_env: Option<String>,
        #[arg(long, default_value = "cc-switch-sync")]
        remote_root: String,
        #[arg(long, default_value = "default")]
        profile: String,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = true)]
        enabled: bool,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = false)]
        auto_sync: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Fetch remote WebDAV manifest info for the saved enabled WebDAV config.
    WebdavRemoteInfo {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List all skills managed by CC Switch.
    List {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Find local skills that exist on disk but are not managed by CC Switch.
    ScanUnmanaged {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Return one installed skill by id.
    Detail {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Check remote content hashes for installed skills with GitHub sources.
    CheckUpdates {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Discover installable skills from enabled CC Switch skill repositories.
    Discover {
        #[arg(long)]
        query: Option<String>,
        #[arg(long, default_value_t = 80)]
        limit: usize,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List configured CC Switch skill repositories.
    RepoList {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Add or replace one configured skill repository.
    RepoAdd {
        #[arg(long)]
        owner: String,
        #[arg(long)]
        name: String,
        #[arg(long, default_value = "main")]
        branch: String,
        #[arg(long, action = clap::ArgAction::Set, default_value_t = true)]
        enabled: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Enable or disable one configured skill repository.
    RepoToggle {
        #[arg(long)]
        owner: String,
        #[arg(long)]
        name: String,
        #[arg(long, action = clap::ArgAction::Set)]
        enabled: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Remove one configured skill repository.
    RepoRemove {
        #[arg(long)]
        owner: String,
        #[arg(long)]
        name: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Install one discoverable skill by key.
    InstallPlan {
        skill_key: String,
        #[arg(long, default_value = "claude")]
        app: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Install one discoverable skill by key.
    Install {
        skill_key: String,
        #[arg(long, default_value = "claude")]
        app: String,
        /// Skip the AgentShield post-install gate. Intended for local development only.
        #[arg(long, action = clap::ArgAction::SetTrue)]
        skip_security_scan: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Update one installed skill from its GitHub source.
    Update {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Uninstall one installed skill.
    Uninstall {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List Popskill stubs.
    StubList {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Convert one installed skill into a Popskill stub.
    Stub {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Restore one Popskill stub from its uninstall backup.
    Rehydrate {
        skill_id: String,
        #[arg(long, default_value = "claude")]
        app: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Run a third-party skill directory through ECC AgentShield.
    SecurityScan {
        skill_dir: String,
        /// Persist this scan result against an installed skill id.
        #[arg(long)]
        skill_id: Option<String>,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List persisted AgentShield scan results for installed skills.
    SecurityScanList {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List uninstall backups created by CC Switch.
    BackupList {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Restore one uninstall backup and enable it for one target app.
    BackupRestore {
        backup_id: String,
        #[arg(long, default_value = "claude")]
        app: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Delete one uninstall backup.
    BackupDelete {
        backup_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Import an unmanaged local skill directory into CC Switch.
    ImportUnmanaged {
        directory: String,
        /// Target apps to enable after import. Can be passed multiple times.
        #[arg(long = "app")]
        apps: Vec<String>,
        /// Skip the AgentShield import gate. Intended for local development only.
        #[arg(long, action = clap::ArgAction::SetTrue)]
        skip_security_scan: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Enable or disable a skill for one target app.
    Toggle {
        skill_id: String,
        #[arg(long)]
        app: String,
        #[arg(long, action = clap::ArgAction::Set)]
        enabled: bool,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
}

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            let payload = ApiResponse::<()>::error("COMMAND_FAILED", format_error(&error));
            eprintln!(
                "{}",
                serde_json::to_string_pretty(&payload).unwrap_or_else(|_| {
                    "{\"ok\":false,\"error\":{\"code\":\"SERIALIZE_ERROR\"}}".to_string()
                })
            );
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let cli = Cli::parse();
    let db = Arc::new(Database::init().context("failed to open CC Switch database")?);

    match cli.command {
        Commands::Health { json: _ } => {
            let skills =
                SkillService::get_all_installed(&db).context("failed to list installed skills")?;
            let unmanaged =
                SkillService::scan_unmanaged(&db).context("failed to scan unmanaged skills")?;
            let backups = SkillService::list_backups().context("failed to list skill backups")?;
            let repositories = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let enabled_repository_count = repositories.iter().filter(|repo| repo.enabled).count();
            let home = std::env::var("HOME").unwrap_or_default();
            print_json(&ApiResponse::ok(json!({
                "sidecarVersion": env!("CARGO_PKG_VERSION"),
                "installedCount": skills.len(),
                "unmanagedCount": unmanaged.len(),
                "backupCount": backups.len(),
                "repositoryCount": repositories.len(),
                "enabledRepositoryCount": enabled_repository_count,
                "skillStorePath": format!("{home}/.cc-switch/skills"),
                "skillBackupPath": format!("{home}/.cc-switch/skill-backups")
            })))
        }
        Commands::WebdavStatus { json: _ } => {
            let settings = cc_switch_lib::get_settings()
                .await
                .map_err(anyhow::Error::msg)?;
            let value = serde_json::to_value(settings).context("failed to serialize settings")?;
            print_json(&ApiResponse::ok(webdav_status_from_settings_value(value)))
        }
        Commands::WebdavConfigure {
            base_url,
            username,
            password_env,
            remote_root,
            profile,
            enabled,
            auto_sync,
            json: _,
        } => {
            let password = read_optional_env_secret("WebDAV password env", password_env)?;
            let settings = cc_switch_lib::get_settings()
                .await
                .map_err(anyhow::Error::msg)?;
            let value = serde_json::to_value(settings).context("failed to serialize settings")?;
            let value = webdav_configured_settings_value(
                value,
                WebDAVConfigureInput {
                    base_url,
                    username,
                    password,
                    remote_root,
                    profile,
                    enabled,
                    auto_sync,
                },
            )?;
            let updated: cc_switch_lib::AppSettings =
                serde_json::from_value(value).context("failed to build CC Switch settings")?;
            cc_switch_lib::save_settings(updated)
                .await
                .map_err(anyhow::Error::msg)
                .context("failed to save WebDAV settings")?;
            let settings = cc_switch_lib::get_settings()
                .await
                .map_err(anyhow::Error::msg)?;
            let value = serde_json::to_value(settings).context("failed to serialize settings")?;
            print_json(&ApiResponse::ok(webdav_status_from_settings_value(value)))
        }
        Commands::WebdavRemoteInfo { json: _ } => {
            let info = cc_switch_lib::webdav_sync_fetch_remote_info()
                .await
                .map_err(anyhow::Error::msg)
                .context("failed to fetch WebDAV remote info")?;
            print_json(&ApiResponse::ok(info))
        }
        Commands::List { json: _ } => {
            let skills =
                SkillService::get_all_installed(&db).context("failed to list installed skills")?;
            print_json(&ApiResponse::ok(skills))
        }
        Commands::ScanUnmanaged { json: _ } => {
            let skills =
                SkillService::scan_unmanaged(&db).context("failed to scan unmanaged skills")?;
            print_json(&ApiResponse::ok(skills))
        }
        Commands::Detail { skill_id, json: _ } => {
            let skill = db
                .get_installed_skill(&skill_id)
                .context("failed to read installed skill")?
                .with_context(|| format!("skill not found: {skill_id}"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::CheckUpdates { json: _ } => {
            let service = SkillService::new();
            let updates = service
                .check_updates(&db)
                .await
                .context("failed to check skill updates")?;
            print_json(&ApiResponse::ok(updates))
        }
        Commands::Discover {
            query,
            limit,
            json: _,
        } => {
            let service = SkillService::new();
            let repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let skills = service
                .list_skills(repos, &db)
                .await
                .context("failed to discover skills")?;
            let normalized_query = query
                .as_deref()
                .map(str::trim)
                .filter(|query| !query.is_empty())
                .map(str::to_lowercase);
            let filtered: Vec<_> = skills
                .into_iter()
                .filter(|skill| {
                    let Some(query) = normalized_query.as_deref() else {
                        return true;
                    };
                    skill.name.to_lowercase().contains(query)
                        || skill.description.to_lowercase().contains(query)
                        || skill.directory.to_lowercase().contains(query)
                        || skill
                            .repo_owner
                            .as_deref()
                            .unwrap_or_default()
                            .to_lowercase()
                            .contains(query)
                        || skill
                            .repo_name
                            .as_deref()
                            .unwrap_or_default()
                            .to_lowercase()
                            .contains(query)
                })
                .take(limit)
                .collect();
            print_json(&ApiResponse::ok(filtered))
        }
        Commands::RepoList { json: _ } => {
            let repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            print_json(&ApiResponse::ok(repos))
        }
        Commands::RepoAdd {
            owner,
            name,
            branch,
            enabled,
            json: _,
        } => {
            let owner = normalize_repository_owner(&owner)?;
            let name = normalize_repository_name(&name)?;
            let branch = normalize_branch(&branch);

            // Infer CC Switch's SkillRepo type from save_skill_repo to avoid patching the submodule.
            let repo = serde_json::from_value(json!({
                "owner": owner,
                "name": name,
                "branch": branch,
                "enabled": enabled
            }))
            .context("failed to build skill repository payload")?;
            db.save_skill_repo(&repo)
                .context("failed to save skill repository")?;
            print_json(&ApiResponse::ok(repo))
        }
        Commands::RepoToggle {
            owner,
            name,
            enabled,
            json: _,
        } => {
            let owner = normalize_repository_owner(&owner)?;
            let name = normalize_repository_name(&name)?;
            let mut repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let repo = repos
                .iter_mut()
                .find(|repo| {
                    repo.owner.eq_ignore_ascii_case(&owner) && repo.name.eq_ignore_ascii_case(&name)
                })
                .with_context(|| format!("skill repository not found: {owner}/{name}"))?;
            repo.enabled = enabled;
            db.save_skill_repo(repo)
                .with_context(|| format!("failed to save skill repository '{owner}/{name}'"))?;
            print_json(&ApiResponse::ok(json!({
                "owner": owner,
                "name": name,
                "enabled": enabled
            })))
        }
        Commands::RepoRemove {
            owner,
            name,
            json: _,
        } => {
            let owner = normalize_repository_owner(&owner)?;
            let name = normalize_repository_name(&name)?;
            db.delete_skill_repo(&owner, &name)
                .with_context(|| format!("failed to remove skill repository '{owner}/{name}'"))?;
            print_json(&ApiResponse::ok(json!({
                "owner": owner,
                "name": name
            })))
        }
        Commands::InstallPlan {
            skill_key,
            app,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            let plan = build_install_plan(&db, &skill_key, &app_type)
                .await
                .with_context(|| format!("failed to plan install for '{skill_key}'"))?;
            print_json(&ApiResponse::ok(plan))
        }
        Commands::Install {
            skill_key,
            app,
            skip_security_scan,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            let service = SkillService::new();
            let repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let skills = service
                .discover_available(repos)
                .await
                .context("failed to discover skills before install")?;
            let skill = skills
                .into_iter()
                .find(|skill| skill.key == skill_key)
                .with_context(|| format!("discoverable skill not found: {skill_key}"))?;
            let installed = service
                .install(&db, &skill, &app_type)
                .await
                .with_context(|| format!("failed to install skill '{skill_key}'"))?;
            if !skip_security_scan {
                let scan = scan_installed_skill(&installed)
                    .with_context(|| format!("failed to run AgentShield for '{skill_key}'"))?;
                if scan.result.status == SecurityScanStatus::Blocked {
                    let _ = SkillService::uninstall(&db, &installed.id);
                    bail!(
                        "AgentShield blocked '{}': {}",
                        installed.name,
                        scan.result.summary
                    );
                }
            }
            print_json(&ApiResponse::ok(installed))
        }
        Commands::Update { skill_id, json: _ } => {
            let service = SkillService::new();
            let skill = service
                .update_skill(&db, &skill_id)
                .await
                .with_context(|| format!("failed to update skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::Uninstall { skill_id, json: _ } => {
            let result = SkillService::uninstall(&db, &skill_id)
                .with_context(|| format!("failed to uninstall skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(result))
        }
        Commands::StubList { json: _ } => {
            let stubs = list_stubbed_skills(&db).context("failed to list Popskill stubs")?;
            print_json(&ApiResponse::ok(stubs))
        }
        Commands::Stub { skill_id, json: _ } => {
            let stub = stub_skill(&db, &skill_id)
                .with_context(|| format!("failed to stub skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(stub))
        }
        Commands::Rehydrate {
            skill_id,
            app,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            let skill = rehydrate_stub(&db, &skill_id, &app_type)
                .with_context(|| format!("failed to rehydrate skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::SecurityScan {
            skill_dir,
            skill_id,
            json: _,
        } => {
            let result = run_security_scan(Path::new(&skill_dir))
                .with_context(|| format!("failed to scan skill directory '{skill_dir}'"))?;
            if let Some(skill_id) = skill_id.as_deref() {
                persist_security_scan(SecurityScanRecord {
                    skill_id: skill_id.to_string(),
                    skill_directory: skill_dir,
                    result: result.clone(),
                })?;
            }
            print_json(&ApiResponse::ok(result))
        }
        Commands::SecurityScanList { json: _ } => {
            let scans = list_security_scans(&db).context("failed to list AgentShield scans")?;
            print_json(&ApiResponse::ok(scans))
        }
        Commands::BackupList { json: _ } => {
            let backups = SkillService::list_backups().context("failed to list skill backups")?;
            print_json(&ApiResponse::ok(backups))
        }
        Commands::BackupRestore {
            backup_id,
            app,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            let skill = SkillService::restore_from_backup(&db, &backup_id, &app_type)
                .with_context(|| format!("failed to restore skill backup '{backup_id}'"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::BackupDelete { backup_id, json: _ } => {
            SkillService::delete_backup(&backup_id)
                .with_context(|| format!("failed to delete skill backup '{backup_id}'"))?;
            print_json(&ApiResponse::ok(json!({ "backupId": backup_id })))
        }
        Commands::ImportUnmanaged {
            directory,
            apps,
            skip_security_scan,
            json: _,
        } => {
            let apps = parse_skill_apps(&apps)?;
            let import_scan = if skip_security_scan {
                None
            } else {
                Some(scan_unmanaged_before_import(&db, &directory)?)
            };
            let imported =
                SkillService::import_from_apps(&db, vec![ImportSkillSelection { directory, apps }])
                    .context("failed to import unmanaged skill")?;
            if let Some(scan) = import_scan {
                persist_import_security_scans(&imported, scan)?;
            }
            print_json(&ApiResponse::ok(imported))
        }
        Commands::Toggle {
            skill_id,
            app,
            enabled,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            SkillService::toggle_app(&db, &skill_id, &app_type, enabled)
                .with_context(|| format!("failed to toggle skill '{skill_id}' for {app}"))?;
            print_json(&ApiResponse::ok(json!({
                "id": skill_id,
                "app": app_type.as_str(),
                "enabled": enabled
            })))
        }
    }
}

fn print_json<T: Serialize>(payload: &ApiResponse<T>) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(payload)?);
    Ok(())
}

fn parse_target_app(app: &str) -> Result<AppType> {
    let app_type =
        AppType::from_str(app).with_context(|| format!("unsupported target app '{app}'"))?;
    if app_type == AppType::OpenClaw {
        bail!("OpenClaw does not support skills");
    }
    Ok(app_type)
}

fn parse_skill_apps(apps: &[String]) -> Result<SkillApps> {
    let targets: Vec<&str> = if apps.is_empty() {
        vec!["claude"]
    } else {
        apps.iter().map(String::as_str).collect()
    };

    let mut skill_apps = SkillApps::default();
    for app in targets {
        let app_type = parse_target_app(app)?;
        skill_apps.set_enabled_for(&app_type, true);
    }
    Ok(skill_apps)
}

fn normalize_required(label: &str, value: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        bail!("{label} is required");
    }
    Ok(trimmed.to_string())
}

fn normalize_with_default(value: &str, default_value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        default_value.to_string()
    } else {
        trimmed.to_string()
    }
}

fn read_optional_env_secret(label: &str, env_name: Option<String>) -> Result<Option<String>> {
    let Some(env_name) = env_name else {
        return Ok(None);
    };

    let env_name = normalize_required(label, &env_name)?;
    std::env::var(&env_name)
        .with_context(|| format!("failed to read {label} '{env_name}'"))
        .map(Some)
}

fn normalize_repository_owner(value: &str) -> Result<String> {
    let owner = normalize_required("repository owner", value)?;
    ensure_valid_repository_segment("repository owner", &owner)?;
    Ok(owner)
}

fn normalize_repository_name(value: &str) -> Result<String> {
    let name = normalize_required("repository name", value)?;
    let name = strip_git_suffix(&name);
    if name.is_empty() {
        bail!("repository name is required");
    }
    ensure_valid_repository_segment("repository name", &name)?;
    Ok(name)
}

fn ensure_valid_repository_segment(label: &str, value: &str) -> Result<()> {
    if value.contains('/') || value.chars().any(char::is_whitespace) {
        bail!("{label} must not contain slashes or whitespace");
    }
    Ok(())
}

fn strip_git_suffix(value: &str) -> String {
    value.strip_suffix(".git").unwrap_or(value).to_string()
}

fn normalize_branch(branch: &str) -> String {
    let trimmed = branch.trim();
    if trimmed.is_empty() {
        "main".to_string()
    } else {
        trimmed.to_string()
    }
}

async fn build_install_plan(
    db: &Arc<Database>,
    skill_key: &str,
    app_type: &AppType,
) -> Result<InstallPlan> {
    let service = SkillService::new();
    let repos = db
        .get_skill_repos()
        .context("failed to load skill repositories")?;
    let skills = service
        .discover_available(repos)
        .await
        .context("failed to discover skills before install plan")?;
    let skill = skills
        .into_iter()
        .find(|skill| skill.key == skill_key)
        .with_context(|| format!("discoverable skill not found: {skill_key}"))?;

    let install_directory = planned_install_directory(&skill.directory);
    let existing = db
        .get_all_installed_skills()
        .context("failed to load installed skills before install plan")?
        .into_values()
        .find(|installed| installed.directory.eq_ignore_ascii_case(&install_directory));
    let ssot_path = SkillService::get_ssot_dir()
        .context("failed to resolve skill storage directory")?
        .join(&install_directory);
    let app_skill_path = SkillService::get_app_skills_dir(app_type)
        .ok()
        .map(|path| path.join(&install_directory).to_string_lossy().to_string());

    Ok(InstallPlan {
        skill_key: skill.key,
        name: skill.name,
        description: skill.description,
        target_app: app_type.as_str().to_string(),
        install_directory,
        source: InstallPlanSource {
            repo_owner: skill.repo_owner,
            repo_name: skill.repo_name,
            repo_branch: skill.repo_branch,
            readme_url: skill.readme_url,
        },
        existing_skill_id: existing.map(|skill| skill.id),
        writes: InstallPlanWrites {
            ssot_path: ssot_path.to_string_lossy().to_string(),
            app_skill_path,
        },
        security_gate: "agentShieldPostInstallRollback".to_string(),
        steps: vec![
            "downloadFromRepository".to_string(),
            "copyToSkillStore".to_string(),
            "enableTargetApp".to_string(),
            "runAgentShield".to_string(),
            "rollbackIfBlocked".to_string(),
        ],
    })
}

fn planned_install_directory(directory: &str) -> String {
    Path::new(directory)
        .file_name()
        .and_then(|name| name.to_str())
        .map(str::to_string)
        .unwrap_or_else(|| directory.trim_matches('/').to_string())
}

fn list_stubbed_skills(db: &Arc<Database>) -> Result<Vec<StubbedSkill>> {
    let mut store = load_stub_store()?;
    let original_count = store.stubs.len();
    let installed = db
        .get_all_installed_skills()
        .context("failed to load installed skills while pruning stubs")?;

    store
        .stubs
        .retain(|stub| !installed.contains_key(&stub.skill.id));
    store
        .stubs
        .sort_by_key(|stub| std::cmp::Reverse(stub.stubbed_at));

    if store.stubs.len() != original_count {
        save_stub_store(&store)?;
    }

    Ok(store.stubs)
}

fn stub_skill(db: &Arc<Database>, skill_id: &str) -> Result<StubbedSkill> {
    let skill = db
        .get_installed_skill(skill_id)
        .context("failed to read installed skill before stubbing")?
        .with_context(|| format!("skill not found: {skill_id}"))?;

    let uninstall_result = SkillService::uninstall(db, skill_id)
        .with_context(|| format!("failed to uninstall skill before stubbing: {skill_id}"))?;
    let backup_path = uninstall_result
        .backup_path
        .with_context(|| format!("CC Switch did not create an uninstall backup for {skill_id}"))?;
    let backup_id = backup_id_from_path(Path::new(&backup_path))?;

    let stub = StubbedSkill {
        skill,
        backup_id,
        backup_path,
        stubbed_at: unix_timestamp(),
    };
    let mut store = load_stub_store()?;
    upsert_stub(&mut store, stub.clone());
    save_stub_store(&store)?;

    Ok(stub)
}

fn rehydrate_stub(
    db: &Arc<Database>,
    skill_id: &str,
    app_type: &AppType,
) -> Result<InstalledSkill> {
    let mut store = load_stub_store()?;
    let stub = remove_stub(&mut store, skill_id)
        .with_context(|| format!("Popskill stub not found: {skill_id}"))?;
    let restored = SkillService::restore_from_backup(db, &stub.backup_id, app_type)
        .with_context(|| format!("failed to restore backup '{}'", stub.backup_id))?;
    save_stub_store(&store)?;

    Ok(restored)
}

fn list_security_scans(db: &Arc<Database>) -> Result<Vec<SecurityScanRecord>> {
    let mut store = load_security_scan_store()?;
    let original_count = store.scans.len();
    let installed = db
        .get_all_installed_skills()
        .context("failed to load installed skills while pruning AgentShield scans")?;

    store
        .scans
        .retain(|scan| installed.contains_key(&scan.skill_id));
    store
        .scans
        .sort_by_key(|scan| std::cmp::Reverse(scan.result.scanned_at));

    if store.scans.len() != original_count {
        save_security_scan_store(&store)?;
    }

    Ok(store.scans)
}

fn scan_installed_skill(skill: &InstalledSkill) -> Result<SecurityScanRecord> {
    let skill_dir = installed_skill_dir(skill)?;
    let result = run_security_scan(&skill_dir)?;
    let record = SecurityScanRecord {
        skill_id: skill.id.clone(),
        skill_directory: skill_dir.to_string_lossy().to_string(),
        result,
    };
    persist_security_scan(record.clone())?;
    Ok(record)
}

fn scan_unmanaged_before_import(db: &Arc<Database>, directory: &str) -> Result<SecurityScanResult> {
    let unmanaged = SkillService::scan_unmanaged(db)
        .context("failed to scan unmanaged skills before import")?
        .into_iter()
        .find(|skill| skill.directory == directory)
        .with_context(|| format!("unmanaged skill not found: {directory}"))?;
    let result = run_security_scan(Path::new(&unmanaged.path))
        .with_context(|| format!("failed to run AgentShield for unmanaged skill '{directory}'"))?;
    if result.status == SecurityScanStatus::Blocked {
        bail!(
            "AgentShield blocked unmanaged skill '{directory}': {}",
            result.summary
        );
    }
    Ok(result)
}

fn persist_import_security_scans(
    imported: &[InstalledSkill],
    result: SecurityScanResult,
) -> Result<()> {
    for skill in imported {
        let skill_dir = installed_skill_dir(skill)?;
        persist_security_scan(SecurityScanRecord {
            skill_id: skill.id.clone(),
            skill_directory: skill_dir.to_string_lossy().to_string(),
            result: result.clone(),
        })?;
    }
    Ok(())
}

fn persist_security_scan(record: SecurityScanRecord) -> Result<()> {
    let mut store = load_security_scan_store()?;
    upsert_security_scan(&mut store, record);
    save_security_scan_store(&store)
}

fn installed_skill_dir(skill: &InstalledSkill) -> Result<PathBuf> {
    Ok(SkillService::get_ssot_dir()
        .context("failed to resolve skill storage directory")?
        .join(&skill.directory))
}

fn backup_id_from_path(path: &Path) -> Result<String> {
    let backup_id = path
        .file_name()
        .and_then(|name| name.to_str())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .with_context(|| format!("backup path has no usable id: {}", path.display()))?;

    if backup_id.contains("..") || backup_id.contains('/') || backup_id.contains('\\') {
        bail!("invalid backup id derived from path: {backup_id}");
    }

    Ok(backup_id.to_string())
}

fn load_stub_store() -> Result<StubStore> {
    load_stub_store_at(&stub_store_path()?)
}

fn save_stub_store(store: &StubStore) -> Result<()> {
    save_stub_store_at(&stub_store_path()?, store)
}

fn load_stub_store_at(path: &Path) -> Result<StubStore> {
    if !path.exists() {
        return Ok(StubStore::default());
    }

    let content = fs::read_to_string(path)
        .with_context(|| format!("failed to read Popskill stub store {}", path.display()))?;
    let store: StubStore = serde_json::from_str(&content)
        .with_context(|| format!("failed to parse Popskill stub store {}", path.display()))?;
    Ok(store)
}

fn save_stub_store_at(path: &Path, store: &StubStore) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create Popskill state directory {}",
                parent.display()
            )
        })?;
    }

    let temp_path = path.with_extension("json.tmp");
    let content = serde_json::to_vec_pretty(store).context("failed to serialize Popskill stubs")?;
    fs::write(&temp_path, content).with_context(|| {
        format!(
            "failed to write Popskill stub store {}",
            temp_path.display()
        )
    })?;
    fs::rename(&temp_path, path)
        .with_context(|| format!("failed to replace Popskill stub store {}", path.display()))?;
    Ok(())
}

fn stub_store_path() -> Result<PathBuf> {
    Ok(home_dir()?.join(".popskill").join("stubs.json"))
}

fn load_security_scan_store() -> Result<SecurityScanStore> {
    load_security_scan_store_at(&security_scan_store_path()?)
}

fn save_security_scan_store(store: &SecurityScanStore) -> Result<()> {
    save_security_scan_store_at(&security_scan_store_path()?, store)
}

fn load_security_scan_store_at(path: &Path) -> Result<SecurityScanStore> {
    if !path.exists() {
        return Ok(SecurityScanStore::default());
    }

    let content = fs::read_to_string(path).with_context(|| {
        format!(
            "failed to read Popskill AgentShield store {}",
            path.display()
        )
    })?;
    let store: SecurityScanStore = serde_json::from_str(&content).with_context(|| {
        format!(
            "failed to parse Popskill AgentShield store {}",
            path.display()
        )
    })?;
    Ok(store)
}

fn save_security_scan_store_at(path: &Path, store: &SecurityScanStore) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create Popskill state directory {}",
                parent.display()
            )
        })?;
    }

    let temp_path = path.with_extension("json.tmp");
    let content =
        serde_json::to_vec_pretty(store).context("failed to serialize AgentShield scans")?;
    fs::write(&temp_path, content).with_context(|| {
        format!(
            "failed to write Popskill AgentShield store {}",
            temp_path.display()
        )
    })?;
    fs::rename(&temp_path, path).with_context(|| {
        format!(
            "failed to replace Popskill AgentShield store {}",
            path.display()
        )
    })?;
    Ok(())
}

fn security_scan_store_path() -> Result<PathBuf> {
    Ok(home_dir()?.join(".popskill").join("security-scans.json"))
}

fn home_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").context("HOME is not set")?;
    if home.trim().is_empty() {
        bail!("HOME is empty");
    }
    Ok(PathBuf::from(home))
}

fn unix_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
}

fn upsert_stub(store: &mut StubStore, stub: StubbedSkill) {
    store
        .stubs
        .retain(|existing| existing.skill.id != stub.skill.id);
    store.stubs.push(stub);
    store
        .stubs
        .sort_by_key(|stub| std::cmp::Reverse(stub.stubbed_at));
}

fn remove_stub(store: &mut StubStore, skill_id: &str) -> Option<StubbedSkill> {
    let index = store
        .stubs
        .iter()
        .position(|stub| stub.skill.id == skill_id)?;
    Some(store.stubs.remove(index))
}

fn upsert_security_scan(store: &mut SecurityScanStore, record: SecurityScanRecord) {
    store
        .scans
        .retain(|existing| existing.skill_id != record.skill_id);
    store.scans.push(record);
    store
        .scans
        .sort_by_key(|scan| std::cmp::Reverse(scan.result.scanned_at));
}

fn run_security_scan(skill_dir: &Path) -> Result<SecurityScanResult> {
    if !skill_dir.exists() {
        bail!("skill directory does not exist: {}", skill_dir.display());
    }
    if !skill_dir.is_dir() {
        bail!("skill path is not a directory: {}", skill_dir.display());
    }

    let command = agent_shield_command(skill_dir);
    let output = Command::new(&command.program).args(&command.args).output();

    match output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let exit_code = output.status.code();
            let status = classify_security_scan(output.status.success(), &stdout, &stderr);
            let summary = scan_summary(status, &stdout, &stderr);

            Ok(SecurityScanResult {
                scanner: "ecc-agentshield".to_string(),
                status,
                summary,
                exit_code,
                stdout,
                stderr,
                scanned_at: unix_timestamp(),
            })
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(SecurityScanResult {
            scanner: "ecc-agentshield".to_string(),
            status: SecurityScanStatus::Unavailable,
            summary: format!(
                "AgentShield command is not available. Install Node/npm or set {}.",
                AGENTSHIELD_BIN_ENV
            ),
            exit_code: None,
            stdout: String::new(),
            stderr: err.to_string(),
            scanned_at: unix_timestamp(),
        }),
        Err(err) => Err(err).context("failed to launch AgentShield"),
    }
}

fn agent_shield_command(skill_dir: &Path) -> AgentShieldCommand {
    if let Ok(program) = std::env::var(AGENTSHIELD_BIN_ENV) {
        let program = program.trim();
        if !program.is_empty() {
            return AgentShieldCommand {
                program: program.to_string(),
                args: vec![skill_dir.to_string_lossy().to_string()],
            };
        }
    }

    AgentShieldCommand {
        program: "npx".to_string(),
        args: vec![
            "--yes".to_string(),
            "ecc-agentshield".to_string(),
            skill_dir.to_string_lossy().to_string(),
        ],
    }
}

fn classify_security_scan(success: bool, stdout: &str, stderr: &str) -> SecurityScanStatus {
    let combined = format!("{stdout}\n{stderr}").to_lowercase();
    if combined.contains("critical")
        || combined.contains("high severity")
        || combined.contains("blocked")
        || combined.contains("danger")
        || combined.contains("malicious")
    {
        return SecurityScanStatus::Blocked;
    }

    if combined.contains("warning")
        || combined.contains("medium severity")
        || combined.contains("low severity")
        || combined.contains("suspicious")
    {
        return SecurityScanStatus::Warning;
    }

    if success {
        SecurityScanStatus::Verified
    } else {
        SecurityScanStatus::Warning
    }
}

fn scan_summary(status: SecurityScanStatus, stdout: &str, stderr: &str) -> String {
    first_non_empty_line(stdout)
        .or_else(|| first_non_empty_line(stderr))
        .unwrap_or_else(|| match status {
            SecurityScanStatus::Verified => {
                "AgentShield completed without reported findings".to_string()
            }
            SecurityScanStatus::Warning => "AgentShield completed with warnings".to_string(),
            SecurityScanStatus::Blocked => "AgentShield reported blocking findings".to_string(),
            SecurityScanStatus::Unavailable => "AgentShield is unavailable".to_string(),
        })
}

fn first_non_empty_line(value: &str) -> Option<String> {
    value
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(ToString::to_string)
}

fn webdav_status_from_settings_value(settings: serde_json::Value) -> serde_json::Value {
    let Some(mut sync) = settings.get("webdavSync").cloned() else {
        return json!({ "configured": false });
    };

    let Some(object) = sync.as_object_mut() else {
        return json!({ "configured": false });
    };

    object.insert("configured".to_string(), json!(true));
    object.remove("password");
    sync
}

struct WebDAVConfigureInput {
    base_url: String,
    username: String,
    password: Option<String>,
    remote_root: String,
    profile: String,
    enabled: bool,
    auto_sync: bool,
}

fn webdav_configured_settings_value(
    mut settings: Value,
    input: WebDAVConfigureInput,
) -> Result<Value> {
    let base_url = normalize_required("WebDAV base URL", &input.base_url)?;
    let username = normalize_required("WebDAV username", &input.username)?;
    let remote_root = normalize_with_default(&input.remote_root, "cc-switch-sync");
    let profile = normalize_with_default(&input.profile, "default");
    let status = settings
        .get("webdavSync")
        .and_then(|sync| sync.get("status"))
        .cloned()
        .unwrap_or_else(|| json!({}));

    let Some(object) = settings.as_object_mut() else {
        bail!("CC Switch settings must be a JSON object");
    };

    object.insert(
        "webdavSync".to_string(),
        json!({
            "enabled": input.enabled,
            "autoSync": input.auto_sync,
            "baseUrl": base_url,
            "username": username,
            "password": input.password.unwrap_or_default(),
            "remoteRoot": remote_root,
            "profile": profile,
            "status": status
        }),
    );

    Ok(settings)
}

fn format_error(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

#[derive(Serialize)]
struct ApiResponse<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<ApiError>,
}

impl<T: Serialize> ApiResponse<T> {
    fn ok(data: T) -> Self {
        Self {
            ok: true,
            data: Some(data),
            error: None,
        }
    }
}

impl ApiResponse<()> {
    fn error(code: &'static str, message: String) -> Self {
        Self {
            ok: false,
            data: None,
            error: Some(ApiError { code, message }),
        }
    }
}

#[derive(Serialize)]
struct ApiError {
    code: &'static str,
    message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StubbedSkill {
    skill: InstalledSkill,
    backup_id: String,
    backup_path: String,
    stubbed_at: i64,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StubStore {
    #[serde(default)]
    stubs: Vec<StubbedSkill>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InstallPlan {
    skill_key: String,
    name: String,
    description: String,
    target_app: String,
    install_directory: String,
    source: InstallPlanSource,
    #[serde(skip_serializing_if = "Option::is_none")]
    existing_skill_id: Option<String>,
    writes: InstallPlanWrites,
    security_gate: String,
    steps: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InstallPlanSource {
    repo_owner: String,
    repo_name: String,
    repo_branch: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    readme_url: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InstallPlanWrites {
    ssot_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    app_skill_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SecurityScanRecord {
    skill_id: String,
    skill_directory: String,
    result: SecurityScanResult,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SecurityScanStore {
    #[serde(default)]
    scans: Vec<SecurityScanRecord>,
}

const AGENTSHIELD_BIN_ENV: &str = "POPSKILL_AGENTSHIELD_BIN";

struct AgentShieldCommand {
    program: String,
    args: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum SecurityScanStatus {
    Verified,
    Warning,
    Blocked,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SecurityScanResult {
    scanner: String,
    status: SecurityScanStatus,
    summary: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    scanned_at: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_target_app_accepts_supported_skill_apps() {
        assert_eq!(parse_target_app(" codex ").unwrap(), AppType::Codex);
        assert_eq!(parse_target_app("HERMES").unwrap(), AppType::Hermes);
    }

    #[test]
    fn parse_target_app_rejects_openclaw_for_skills() {
        let message = parse_target_app("openclaw").unwrap_err().to_string();
        assert!(message.contains("OpenClaw does not support skills"));
    }

    #[test]
    fn parse_skill_apps_defaults_to_claude() {
        let apps = parse_skill_apps(&[]).unwrap();
        assert!(apps.claude);
        assert!(!apps.codex);
        assert!(!apps.gemini);
        assert!(!apps.opencode);
        assert!(!apps.hermes);
    }

    #[test]
    fn parse_skill_apps_accumulates_requested_targets() {
        let apps = parse_skill_apps(&["codex".to_string(), "gemini".to_string()]).unwrap();
        assert!(!apps.claude);
        assert!(apps.codex);
        assert!(apps.gemini);
        assert!(!apps.opencode);
        assert!(!apps.hermes);
    }

    #[test]
    fn normalize_required_trims_non_empty_values() {
        assert_eq!(
            normalize_required("repository owner", "  maojiebc  ").unwrap(),
            "maojiebc"
        );
    }

    #[test]
    fn normalize_required_rejects_blank_values() {
        let message = normalize_required("repository name", " \n\t ")
            .unwrap_err()
            .to_string();
        assert!(message.contains("repository name is required"));
    }

    #[test]
    fn normalize_repository_owner_rejects_invalid_segments() {
        let message = normalize_repository_owner("owner/repo")
            .unwrap_err()
            .to_string();
        assert!(message.contains("repository owner must not contain slashes or whitespace"));
    }

    #[test]
    fn normalize_repository_name_strips_only_git_suffix() {
        assert_eq!(
            normalize_repository_name(" widget.git-tools.git ").unwrap(),
            "widget.git-tools"
        );
    }

    #[test]
    fn normalize_repository_name_rejects_empty_name_after_stripping() {
        let message = normalize_repository_name(".git").unwrap_err().to_string();
        assert!(message.contains("repository name is required"));
    }

    #[test]
    fn normalize_repository_name_rejects_invalid_segments() {
        let message = normalize_repository_name("bad repo")
            .unwrap_err()
            .to_string();
        assert!(message.contains("repository name must not contain slashes or whitespace"));
    }

    #[test]
    fn normalize_branch_defaults_blank_values_to_main() {
        assert_eq!(normalize_branch(" \n\t "), "main");
        assert_eq!(normalize_branch(" dev "), "dev");
    }

    #[test]
    fn planned_install_directory_uses_last_path_segment() {
        assert_eq!(
            planned_install_directory("skills/nested-demo"),
            "nested-demo"
        );
        assert_eq!(planned_install_directory("root-demo"), "root-demo");
    }

    #[test]
    fn format_error_includes_context_chain() {
        let error = anyhow::anyhow!("root cause").context("outer context");
        assert_eq!(format_error(&error), "outer context: root cause");
    }

    #[test]
    fn backup_id_from_path_uses_last_path_segment() {
        let backup_id = backup_id_from_path(Path::new("/tmp/20260513_demo-skill")).unwrap();

        assert_eq!(backup_id, "20260513_demo-skill");
    }

    #[test]
    fn backup_id_from_path_rejects_empty_paths() {
        let message = backup_id_from_path(Path::new("/")).unwrap_err().to_string();

        assert!(message.contains("backup path has no usable id"));
    }

    #[test]
    fn upsert_stub_replaces_existing_skill_and_sorts_newest_first() {
        let mut store = StubStore::default();
        upsert_stub(&mut store, stub_fixture("older", 10));
        upsert_stub(&mut store, stub_fixture("newer", 30));
        upsert_stub(&mut store, stub_fixture("older", 40));

        assert_eq!(store.stubs.len(), 2);
        assert_eq!(store.stubs[0].skill.id, "older");
        assert_eq!(store.stubs[0].stubbed_at, 40);
        assert_eq!(store.stubs[1].skill.id, "newer");
    }

    #[test]
    fn remove_stub_returns_and_removes_matching_entry() {
        let mut store = StubStore {
            stubs: vec![stub_fixture("skill-a", 10), stub_fixture("skill-b", 20)],
        };

        let removed = remove_stub(&mut store, "skill-a").unwrap();

        assert_eq!(removed.skill.id, "skill-a");
        assert_eq!(store.stubs.len(), 1);
        assert_eq!(store.stubs[0].skill.id, "skill-b");
    }

    #[test]
    fn classify_security_scan_blocks_high_risk_output() {
        let status = classify_security_scan(true, "High severity shell execution", "");

        assert_eq!(status, SecurityScanStatus::Blocked);
    }

    #[test]
    fn classify_security_scan_warns_on_nonzero_without_blocking_words() {
        let status = classify_security_scan(false, "scan completed with warnings", "");

        assert_eq!(status, SecurityScanStatus::Warning);
    }

    #[test]
    fn classify_security_scan_verifies_clean_success() {
        let status = classify_security_scan(true, "all checks passed", "");

        assert_eq!(status, SecurityScanStatus::Verified);
    }

    #[test]
    fn scan_summary_prefers_first_stdout_line() {
        let summary = scan_summary(
            SecurityScanStatus::Warning,
            "\n  first finding\nsecond",
            "stderr",
        );

        assert_eq!(summary, "first finding");
    }

    #[test]
    fn upsert_security_scan_replaces_existing_skill_and_sorts_newest_first() {
        let mut store = SecurityScanStore::default();

        upsert_security_scan(&mut store, security_scan_fixture("older", 10));
        upsert_security_scan(&mut store, security_scan_fixture("newer", 30));
        upsert_security_scan(&mut store, security_scan_fixture("older", 40));

        assert_eq!(store.scans.len(), 2);
        assert_eq!(store.scans[0].skill_id, "older");
        assert_eq!(store.scans[0].result.scanned_at, 40);
        assert_eq!(store.scans[1].skill_id, "newer");
    }

    #[test]
    fn webdav_status_reports_unconfigured_when_missing() {
        let status = webdav_status_from_settings_value(json!({}));

        assert_eq!(status, json!({ "configured": false }));
    }

    #[test]
    fn webdav_status_removes_password_and_marks_configured() {
        let status = webdav_status_from_settings_value(json!({
            "webdavSync": {
                "enabled": true,
                "baseUrl": "https://dav.example.com",
                "username": "demo",
                "password": "secret"
            }
        }));

        assert_eq!(status["configured"], true);
        assert_eq!(status["enabled"], true);
        assert!(status.get("password").is_none());
    }

    #[test]
    fn webdav_configure_payload_preserves_status_and_defaults_blank_fields() {
        let payload = webdav_configured_settings_value(
            json!({
                "theme": "system",
                "webdavSync": {
                    "enabled": true,
                    "baseUrl": "https://old.example.com",
                    "username": "old",
                    "password": "",
                    "remoteRoot": "old-root",
                    "profile": "old-profile",
                    "status": {
                        "lastSyncAt": 1778603190,
                        "lastError": null
                    }
                }
            }),
            WebDAVConfigureInput {
                base_url: " https://dav.example.com ".to_string(),
                username: " demo ".to_string(),
                password: None,
                remote_root: " ".to_string(),
                profile: "\n".to_string(),
                enabled: true,
                auto_sync: false,
            },
        )
        .unwrap();

        assert_eq!(payload["theme"], "system");
        assert_eq!(payload["webdavSync"]["baseUrl"], "https://dav.example.com");
        assert_eq!(payload["webdavSync"]["username"], "demo");
        assert_eq!(payload["webdavSync"]["password"], "");
        assert_eq!(payload["webdavSync"]["remoteRoot"], "cc-switch-sync");
        assert_eq!(payload["webdavSync"]["profile"], "default");
        assert_eq!(payload["webdavSync"]["status"]["lastSyncAt"], 1778603190);
    }

    #[test]
    fn webdav_configure_payload_uses_env_password_without_sanitizing_it() {
        let payload = webdav_configured_settings_value(
            json!({}),
            WebDAVConfigureInput {
                base_url: "https://dav.example.com".to_string(),
                username: "demo".to_string(),
                password: Some(" secret with spaces ".to_string()),
                remote_root: "root".to_string(),
                profile: "profile".to_string(),
                enabled: false,
                auto_sync: true,
            },
        )
        .unwrap();

        assert_eq!(payload["webdavSync"]["enabled"], false);
        assert_eq!(payload["webdavSync"]["autoSync"], true);
        assert_eq!(payload["webdavSync"]["password"], " secret with spaces ");
    }

    #[test]
    fn webdav_configure_payload_requires_url_and_username() {
        let message = webdav_configured_settings_value(
            json!({}),
            WebDAVConfigureInput {
                base_url: " ".to_string(),
                username: "demo".to_string(),
                password: None,
                remote_root: "root".to_string(),
                profile: "profile".to_string(),
                enabled: true,
                auto_sync: false,
            },
        )
        .unwrap_err()
        .to_string();

        assert!(message.contains("WebDAV base URL is required"));
    }

    fn stub_fixture(id: &str, stubbed_at: i64) -> StubbedSkill {
        StubbedSkill {
            skill: InstalledSkill {
                id: id.to_string(),
                name: id.to_string(),
                description: Some("demo".to_string()),
                directory: id.to_string(),
                repo_owner: Some("owner".to_string()),
                repo_name: Some("repo".to_string()),
                repo_branch: Some("main".to_string()),
                readme_url: None,
                apps: SkillApps::default(),
                installed_at: 1,
                content_hash: Some("hash".to_string()),
                updated_at: 0,
            },
            backup_id: format!("backup-{id}"),
            backup_path: format!("/tmp/backup-{id}"),
            stubbed_at,
        }
    }

    fn security_scan_fixture(skill_id: &str, scanned_at: i64) -> SecurityScanRecord {
        SecurityScanRecord {
            skill_id: skill_id.to_string(),
            skill_directory: format!("/tmp/{skill_id}"),
            result: SecurityScanResult {
                scanner: "ecc-agentshield".to_string(),
                status: SecurityScanStatus::Verified,
                summary: "ok".to_string(),
                exit_code: Some(0),
                stdout: String::new(),
                stderr: String::new(),
                scanned_at,
            },
        }
    }
}
