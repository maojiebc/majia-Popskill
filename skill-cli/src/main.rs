use anyhow::{Context, Result, bail};
use cc_switch_lib::{
    AppType, Database, ImportSkillSelection, InstalledSkill, SkillApps, SkillService,
};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::env;
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
    /// Return Popskill's canonical asset-control-plane schema.
    DomainSchema {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
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
    /// Explain current WebDAV manual sync readiness without uploading or downloading.
    WebdavSyncPlan {
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
    /// List capability packages, including composite built-ins and standalone skill wrappers.
    PackageList {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Return one capability package by id.
    PackageDetail {
        package_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Preview installing one capability package. This v0.3 self-use path is read-only.
    PackageInstall {
        package_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Preview configuring one capability package without writing secrets.
    PackageConfig {
        package_id: String,
        #[arg(long)]
        key: String,
        #[arg(long)]
        value_env: Option<String>,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List local Claude Code agents from ~/.claude/agents.
    AgentList {
        /// Optional agents directory override for tests or alternate Claude homes.
        #[arg(long)]
        root: Option<String>,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// List Agent-capable tool targets and their local paths.
    AgentTargets {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Discover read-only Agent definitions from AgencyAgents.
    AgentCatalog {
        #[arg(long)]
        query: Option<String>,
        #[arg(long, default_value_t = 80)]
        limit: usize,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Preview an AgencyAgents install without writing files.
    AgentInstallPlan {
        agent_key: String,
        #[arg(long, default_value = "claude-code")]
        target: String,
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
        Commands::DomainSchema { json: _ } => print_json(&ApiResponse::ok(domain_schema())),
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
        Commands::WebdavSyncPlan { json: _ } => {
            let settings = cc_switch_lib::get_settings()
                .await
                .map_err(anyhow::Error::msg)?;
            let value = serde_json::to_value(settings).context("failed to serialize settings")?;
            print_json(&ApiResponse::ok(webdav_sync_plan_from_settings_value(
                value,
            )))
        }
        Commands::List { json: _ } => {
            let skills =
                SkillService::get_all_installed(&db).context("failed to list installed skills")?;
            let enriched: Vec<EnrichedInstalledSkill> =
                skills.into_iter().map(enrich_installed_skill).collect();
            print_json(&ApiResponse::ok(enriched))
        }
        Commands::PackageList { json: _ } => {
            let packages = list_capability_packages(&db)?;
            print_json(&ApiResponse::ok(packages))
        }
        Commands::PackageDetail {
            package_id,
            json: _,
        } => {
            let package = find_capability_package(&db, &package_id)?;
            print_json(&ApiResponse::ok(package))
        }
        Commands::PackageInstall {
            package_id,
            json: _,
        } => {
            let package = find_capability_package(&db, &package_id)?;
            let result = build_package_install_result(&package);
            print_json(&ApiResponse::ok(result))
        }
        Commands::PackageConfig {
            package_id,
            key,
            value_env,
            json: _,
        } => {
            let package = find_capability_package(&db, &package_id)?;
            let result = build_package_config_result(&package, &key, value_env)?;
            print_json(&ApiResponse::ok(result))
        }
        Commands::AgentList { root, json: _ } => {
            let root = match root {
                Some(root) => PathBuf::from(root),
                None => claude_agents_dir()?,
            };
            let agents = list_local_agents(&root)
                .with_context(|| format!("failed to list agents in {}", root.display()))?;
            print_json(&ApiResponse::ok(agents))
        }
        Commands::AgentTargets { json: _ } => {
            let targets = list_agent_targets()?;
            print_json(&ApiResponse::ok(targets))
        }
        Commands::AgentCatalog {
            query,
            limit,
            json: _,
        } => {
            let agents = discover_agency_agents(query.as_deref(), limit).await?;
            print_json(&ApiResponse::ok(agents))
        }
        Commands::AgentInstallPlan {
            agent_key,
            target,
            json: _,
        } => {
            let plan = build_agent_install_plan(&agent_key, &target)?;
            print_json(&ApiResponse::ok(plan))
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

fn claude_agents_dir() -> Result<PathBuf> {
    Ok(home_dir()?.join(".claude").join("agents"))
}

fn list_local_agents(root: &Path) -> Result<Vec<LocalAgent>> {
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut files = Vec::new();
    collect_agent_markdown_files(root, &mut files)
        .with_context(|| format!("failed to scan {}", root.display()))?;

    let mut agents = Vec::new();
    for path in files {
        let content = fs::read_to_string(&path)
            .with_context(|| format!("failed to read agent file {}", path.display()))?;
        let metadata = fs::metadata(&path)
            .with_context(|| format!("failed to read agent metadata {}", path.display()))?;
        agents.push(local_agent_from_markdown(root, &path, &content, &metadata)?);
    }

    agents.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(agents)
}

fn collect_agent_markdown_files(root: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(root).with_context(|| format!("failed to read {}", root.display()))? {
        let entry = entry.with_context(|| format!("failed to read entry in {}", root.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", path.display()))?;

        if file_type.is_dir() {
            collect_agent_markdown_files(&path, files)?;
        } else if file_type.is_file()
            && path
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| extension.eq_ignore_ascii_case("md"))
        {
            files.push(path);
        }
    }
    Ok(())
}

fn local_agent_from_markdown(
    root: &Path,
    path: &Path,
    content: &str,
    metadata: &fs::Metadata,
) -> Result<LocalAgent> {
    let parsed = parse_agent_markdown(content);
    let file_stem = path
        .file_stem()
        .and_then(|name| name.to_str())
        .context("agent file must have a UTF-8 stem")?;
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .context("agent file must have a UTF-8 name")?
        .to_string();
    let relative_path = path
        .strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .to_string();
    let id = strip_markdown_suffix(&relative_path);
    let category = path
        .strip_prefix(root)
        .ok()
        .and_then(|relative| relative.parent())
        .and_then(|parent| parent.components().next())
        .map(|component| component.as_os_str().to_string_lossy().to_string())
        .filter(|category| !category.is_empty())
        .unwrap_or_else(|| "local".to_string());

    Ok(LocalAgent {
        id,
        name: parsed.name.unwrap_or_else(|| title_from_slug(file_stem)),
        description: parsed.description.unwrap_or_else(|| {
            first_markdown_paragraph(content)
                .unwrap_or_else(|| "Local Claude Code agent".to_string())
        }),
        file_name,
        path: path.to_string_lossy().to_string(),
        category,
        tools: parsed.tools,
        model: parsed.model,
        last_modified_at: metadata
            .modified()
            .ok()
            .and_then(system_time_to_unix_timestamp),
        size_bytes: metadata.len(),
    })
}

fn strip_markdown_suffix(value: &str) -> String {
    value
        .strip_suffix(".md")
        .or_else(|| value.strip_suffix(".MD"))
        .unwrap_or(value)
        .to_string()
}

fn title_from_slug(value: &str) -> String {
    value
        .replace(['-', '_'], " ")
        .split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn system_time_to_unix_timestamp(value: SystemTime) -> Option<i64> {
    value
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|duration| i64::try_from(duration.as_secs()).ok())
}

fn list_agent_targets() -> Result<Vec<AgentTarget>> {
    let home = home_dir()?;
    let cwd = env::current_dir().unwrap_or_else(|_| home.clone());
    Ok(agent_targets_for_paths(&home, &cwd, command_exists))
}

fn agent_targets_for_paths<F>(home: &Path, cwd: &Path, command_exists: F) -> Vec<AgentTarget>
where
    F: Fn(&str) -> bool,
{
    let home_path = |relative: &str| home.join(relative).to_string_lossy().to_string();
    let cwd_path = |relative: &str| cwd.join(relative).to_string_lossy().to_string();
    let has_home_dir = |relative: &str| home.join(relative).exists();
    let has_cwd_path = |relative: &str| cwd.join(relative).exists();

    vec![
        AgentTarget {
            id: "claude-code".to_string(),
            name: "Claude Code".to_string(),
            scope: "user".to_string(),
            format: "markdown-agent".to_string(),
            paths: vec![home_path(".claude/agents")],
            detected: has_home_dir(".claude"),
            source: "agency-agents".to_string(),
            note: Some("AgencyAgents copies markdown agents here directly.".to_string()),
        },
        AgentTarget {
            id: "copilot".to_string(),
            name: "GitHub Copilot".to_string(),
            scope: "user".to_string(),
            format: "markdown-agent".to_string(),
            paths: vec![home_path(".github/agents"), home_path(".copilot/agents")],
            detected: command_exists("code") || has_home_dir(".github") || has_home_dir(".copilot"),
            source: "agency-agents".to_string(),
            note: Some("VS Code may need chat.agentFilesLocations configured.".to_string()),
        },
        AgentTarget {
            id: "antigravity".to_string(),
            name: "Antigravity".to_string(),
            scope: "user".to_string(),
            format: "skill".to_string(),
            paths: vec![home_path(".gemini/antigravity/skills")],
            detected: has_home_dir(".gemini/antigravity/skills"),
            source: "agency-agents".to_string(),
            note: Some("AgencyAgents converts agents into Antigravity skills.".to_string()),
        },
        AgentTarget {
            id: "gemini-cli".to_string(),
            name: "Gemini CLI".to_string(),
            scope: "user".to_string(),
            format: "extension".to_string(),
            paths: vec![home_path(".gemini/extensions/agency-agents")],
            detected: command_exists("gemini") || has_home_dir(".gemini"),
            source: "agency-agents".to_string(),
            note: None,
        },
        AgentTarget {
            id: "opencode".to_string(),
            name: "OpenCode".to_string(),
            scope: "project".to_string(),
            format: "markdown-agent".to_string(),
            paths: vec![cwd_path(".opencode/agents")],
            detected: command_exists("opencode") || has_home_dir(".config/opencode"),
            source: "agency-agents".to_string(),
            note: Some(
                "Project-scoped target; run Popskill from the project root for this path."
                    .to_string(),
            ),
        },
        AgentTarget {
            id: "openclaw".to_string(),
            name: "OpenClaw".to_string(),
            scope: "user".to_string(),
            format: "workspace".to_string(),
            paths: vec![home_path(".openclaw/agency-agents")],
            detected: command_exists("openclaw") || has_home_dir(".openclaw"),
            source: "agency-agents".to_string(),
            note: Some("OpenClaw uses generated workspace folders.".to_string()),
        },
        AgentTarget {
            id: "cursor".to_string(),
            name: "Cursor".to_string(),
            scope: "project".to_string(),
            format: "rule".to_string(),
            paths: vec![cwd_path(".cursor/rules")],
            detected: command_exists("cursor")
                || has_home_dir(".cursor")
                || has_cwd_path(".cursor"),
            source: "agency-agents".to_string(),
            note: Some("Project-scoped rules target.".to_string()),
        },
        AgentTarget {
            id: "aider".to_string(),
            name: "Aider".to_string(),
            scope: "project".to_string(),
            format: "conventions".to_string(),
            paths: vec![cwd_path("CONVENTIONS.md")],
            detected: command_exists("aider") || has_cwd_path("CONVENTIONS.md"),
            source: "agency-agents".to_string(),
            note: Some("AgencyAgents emits one project-level conventions file.".to_string()),
        },
        AgentTarget {
            id: "windsurf".to_string(),
            name: "Windsurf".to_string(),
            scope: "project".to_string(),
            format: "rule".to_string(),
            paths: vec![cwd_path(".windsurfrules")],
            detected: command_exists("windsurf")
                || has_home_dir(".codeium")
                || has_cwd_path(".windsurfrules"),
            source: "agency-agents".to_string(),
            note: Some("Project-scoped rules file.".to_string()),
        },
        AgentTarget {
            id: "qwen".to_string(),
            name: "Qwen Code".to_string(),
            scope: "user/project".to_string(),
            format: "markdown-agent".to_string(),
            paths: vec![home_path(".qwen/agents"), cwd_path(".qwen/agents")],
            detected: command_exists("qwen") || has_home_dir(".qwen") || has_cwd_path(".qwen"),
            source: "agency-agents".to_string(),
            note: Some(
                "AgencyAgents supports both user-wide and project-scoped Qwen agents.".to_string(),
            ),
        },
        AgentTarget {
            id: "kimi".to_string(),
            name: "Kimi Code".to_string(),
            scope: "user".to_string(),
            format: "agent-yaml".to_string(),
            paths: vec![home_path(".config/kimi/agents")],
            detected: command_exists("kimi") || has_home_dir(".config/kimi"),
            source: "agency-agents".to_string(),
            note: Some("AgencyAgents emits agent.yaml plus system.md per agent.".to_string()),
        },
    ]
}

fn command_exists(command: &str) -> bool {
    let Some(paths) = env::var_os("PATH") else {
        return false;
    };
    env::split_paths(&paths).any(|path| path.join(command).is_file())
}

const AGENCY_AGENTS_REPO_OWNER: &str = "msitarzewski";
const AGENCY_AGENTS_REPO_NAME: &str = "agency-agents";
const AGENCY_AGENTS_BRANCH: &str = "main";
const AGENCY_AGENTS_TREE_URL: &str =
    "https://api.github.com/repos/msitarzewski/agency-agents/git/trees/main?recursive=1";
const AGENCY_AGENT_CATEGORIES: &[&str] = &[
    "academic",
    "design",
    "engineering",
    "finance",
    "game-development",
    "marketing",
    "paid-media",
    "product",
    "project-management",
    "sales",
    "spatial-computing",
    "specialized",
    "strategy",
    "support",
    "testing",
];

async fn discover_agency_agents(query: Option<&str>, limit: usize) -> Result<Vec<CatalogAgent>> {
    if limit == 0 {
        return Ok(Vec::new());
    }

    let client = reqwest::Client::builder()
        .user_agent("Popskill/0.1")
        .build()
        .context("failed to build GitHub client")?;
    let mut request = client.get(AGENCY_AGENTS_TREE_URL);
    if let Some(token) = github_token() {
        request = request.bearer_auth(token);
    }

    let response = request
        .send()
        .await
        .context("failed to fetch AgencyAgents tree")?;
    if response.status() == reqwest::StatusCode::FORBIDDEN {
        bail!(
            "AgencyAgents GitHub API rate limit exceeded. Set GITHUB_TOKEN or GH_TOKEN for authenticated requests."
        );
    }
    let response = response
        .error_for_status()
        .context("AgencyAgents tree request failed")?
        .json::<GitHubTreeResponse>()
        .await
        .context("failed to parse AgencyAgents tree")?;

    let normalized_query = query
        .map(|query| query.trim().to_lowercase())
        .filter(|query| !query.is_empty());
    let mut agents: Vec<CatalogAgent> = response
        .tree
        .into_iter()
        .filter_map(|entry| catalog_agent_from_tree_path(&entry.path, &entry.kind))
        .filter(|agent| agent_matches_query(agent, normalized_query.as_deref()))
        .take(limit)
        .collect();

    for agent in &mut agents {
        if let Ok(content) = fetch_agency_agent_markdown(&client, &agent.path).await {
            let parsed = parse_agent_markdown(&content);
            if let Some(name) = parsed.name {
                agent.name = name;
            }
            if let Some(description) = parsed.description {
                agent.description = description;
            }
            agent.tools = parsed.tools;
            agent.model = parsed.model;
        }
    }

    Ok(agents)
}

async fn fetch_agency_agent_markdown(client: &reqwest::Client, path: &str) -> Result<String> {
    let url = agency_agent_raw_url(path);
    client
        .get(url)
        .send()
        .await
        .with_context(|| format!("failed to fetch AgencyAgents agent {path}"))?
        .error_for_status()
        .with_context(|| format!("AgencyAgents agent request failed for {path}"))?
        .text()
        .await
        .with_context(|| format!("failed to read AgencyAgents agent {path}"))
}

fn catalog_agent_from_tree_path(path: &str, kind: &str) -> Option<CatalogAgent> {
    if kind != "blob" || !path.ends_with(".md") {
        return None;
    }

    let (category, file_name) = path.split_once('/')?;
    if !AGENCY_AGENT_CATEGORIES.contains(&category) || file_name.contains('/') {
        return None;
    }

    let file_stem = Path::new(file_name).file_stem()?.to_str()?;
    let directory = strip_markdown_suffix(path);
    Some(CatalogAgent {
        id: format!("{AGENCY_AGENTS_REPO_OWNER}/{AGENCY_AGENTS_REPO_NAME}:{directory}"),
        name: title_from_slug(file_stem),
        description: format!("AgencyAgents {} agent", title_from_slug(category)),
        path: path.to_string(),
        category: category.to_string(),
        repo_owner: AGENCY_AGENTS_REPO_OWNER.to_string(),
        repo_name: AGENCY_AGENTS_REPO_NAME.to_string(),
        repo_branch: AGENCY_AGENTS_BRANCH.to_string(),
        readme_url: agency_agent_readme_url(path),
        raw_url: agency_agent_raw_url(path),
        tools: Vec::new(),
        model: None,
        source: "agency-agents".to_string(),
    })
}

fn agent_matches_query(agent: &CatalogAgent, query: Option<&str>) -> bool {
    let Some(query) = query else {
        return true;
    };

    agent.name.to_lowercase().contains(query)
        || agent.description.to_lowercase().contains(query)
        || agent.category.to_lowercase().contains(query)
        || agent.path.to_lowercase().contains(query)
}

fn agency_agent_readme_url(path: &str) -> String {
    format!(
        "https://github.com/{AGENCY_AGENTS_REPO_OWNER}/{AGENCY_AGENTS_REPO_NAME}/blob/{AGENCY_AGENTS_BRANCH}/{path}"
    )
}

fn agency_agent_raw_url(path: &str) -> String {
    format!(
        "https://raw.githubusercontent.com/{AGENCY_AGENTS_REPO_OWNER}/{AGENCY_AGENTS_REPO_NAME}/{AGENCY_AGENTS_BRANCH}/{path}"
    )
}

fn github_token() -> Option<String> {
    env::var("GITHUB_TOKEN")
        .ok()
        .or_else(|| env::var("GH_TOKEN").ok())
        .map(|token| token.trim().to_string())
        .filter(|token| !token.is_empty())
}

fn build_agent_install_plan(agent_key: &str, target_id: &str) -> Result<AgentInstallPlan> {
    let agent = agency_agent_from_key(agent_key)?;
    let target = list_agent_targets()?
        .into_iter()
        .find(|target| target.id == target_id)
        .with_context(|| format!("unsupported agent target: {target_id}"))?;
    let writes = target_destination_paths(&target, &agent.path)?;
    let conflicts = writes
        .iter()
        .filter(|path| Path::new(path.as_str()).exists())
        .cloned()
        .collect::<Vec<_>>();
    let mut steps = vec!["fetchFromAgencyAgents".to_string()];
    if target.format != "markdown-agent" {
        steps.push("convertForTargetFormat".to_string());
    }
    steps.push("writeAgentFile".to_string());

    Ok(AgentInstallPlan {
        agent_id: agent.id.clone(),
        name: agent.name.clone(),
        target_id: target.id.clone(),
        target_name: target.name.clone(),
        target_format: target.format.clone(),
        source: AgentInstallSource {
            repo_owner: agent.repo_owner,
            repo_name: agent.repo_name,
            repo_branch: agent.repo_branch,
            path: agent.path,
            raw_url: agent.raw_url,
        },
        writes,
        conflict: if conflicts.is_empty() {
            None
        } else {
            Some(AgentInstallConflict { paths: conflicts })
        },
        requires_conversion: target.format != "markdown-agent",
        steps,
    })
}

fn agency_agent_from_key(agent_key: &str) -> Result<CatalogAgent> {
    let path = agent_key
        .split_once(':')
        .map(|(_, path)| path)
        .unwrap_or(agent_key)
        .trim()
        .trim_start_matches('/');
    let path = if path.ends_with(".md") {
        path.to_string()
    } else {
        format!("{path}.md")
    };
    catalog_agent_from_tree_path(&path, "blob")
        .with_context(|| format!("unsupported AgencyAgents agent key: {agent_key}"))
}

fn target_destination_paths(target: &AgentTarget, agent_path: &str) -> Result<Vec<String>> {
    let file_name = Path::new(agent_path)
        .file_name()
        .and_then(|name| name.to_str())
        .context("agent path must have a UTF-8 file name")?;

    Ok(target
        .paths
        .iter()
        .map(|path| {
            let target_path = Path::new(path);
            if target_path.extension().is_some() {
                path.clone()
            } else {
                target_path.join(file_name).to_string_lossy().to_string()
            }
        })
        .collect())
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

fn list_capability_packages(db: &Arc<Database>) -> Result<Vec<CapabilityPackage>> {
    let skills = SkillService::get_all_installed(db).context("failed to list installed skills")?;
    let agents = list_local_agents(&claude_agents_dir()?).unwrap_or_default();
    let mut packages = vec![
        lark_capability_package(&skills, &agents),
        pdf_capability_package(&skills),
    ];
    if let Some(package) = baoyu_capability_package(&skills) {
        packages.push(package);
    }

    packages.extend(
        skills
            .iter()
            .filter(|skill| !is_baoyu_package_skill(skill))
            .map(standalone_skill_package),
    );
    packages.sort_by(|left, right| {
        package_sort_rank(left)
            .cmp(&package_sort_rank(right))
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(packages)
}

fn find_capability_package(db: &Arc<Database>, package_id: &str) -> Result<CapabilityPackage> {
    let normalized_id = package_id.trim();
    list_capability_packages(db)?
        .into_iter()
        .find(|package| package.id.eq_ignore_ascii_case(normalized_id))
        .with_context(|| format!("capability package not found: {package_id}"))
}

fn package_sort_rank(package: &CapabilityPackage) -> u8 {
    match package.package_type {
        CapabilityPackageType::Composite => 0,
        CapabilityPackageType::Standalone => {
            if package.source.kind == "builtin" {
                1
            } else {
                2
            }
        }
    }
}

fn baoyu_capability_package(skills: &[InstalledSkill]) -> Option<CapabilityPackage> {
    let mut package_skills = skills
        .iter()
        .filter(|skill| is_baoyu_package_skill(skill))
        .collect::<Vec<_>>();
    if package_skills.is_empty() {
        return None;
    }

    package_skills.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.id.cmp(&right.id))
    });

    let repo_branch = package_skills
        .iter()
        .filter_map(|skill| skill.repo_branch.as_deref())
        .find(|branch| !branch.trim().is_empty() && !branch.eq_ignore_ascii_case("HEAD"))
        .unwrap_or("main");
    let skill_components = package_skills
        .iter()
        .map(|skill| {
            package_component(
                "skill",
                &skill.id,
                &skill.name,
                true,
                true,
                "installed",
                Some(&skill.directory),
            )
        })
        .collect::<Vec<_>>();

    Some(CapabilityPackage {
        id: "pkg:jimliu/baoyu-skills".to_string(),
        package_type: CapabilityPackageType::Composite,
        name: "Baoyu Skills".to_string(),
        vendor: Some("jimliu".to_string()),
        summary: "Composite creator and publishing skill suite maintained in the jimliu/baoyu-skills GitHub repository.".to_string(),
        source: PackageSource {
            kind: "github".to_string(),
            location: "jimliu/baoyu-skills".to_string(),
            update_strategy: "git".to_string(),
            repo_owner: Some("jimliu".to_string()),
            repo_name: Some("baoyu-skills".to_string()),
            repo_branch: Some(repo_branch.to_string()),
            readme_url: Some("https://github.com/jimliu/baoyu-skills".to_string()),
        },
        components: PackageComponents {
            cli: Vec::new(),
            skills: skill_components,
            mcp: Vec::new(),
            agents: Vec::new(),
        },
        config_schema: Vec::new(),
        installed: true,
        lifecycle: lifecycle_from_skills(package_skills),
    })
}

fn is_baoyu_package_skill(skill: &InstalledSkill) -> bool {
    let repo_matches = skill
        .repo_owner
        .as_deref()
        .zip(skill.repo_name.as_deref())
        .map(|(owner, name)| {
            owner.eq_ignore_ascii_case("jimliu") && name.eq_ignore_ascii_case("baoyu-skills")
        })
        .unwrap_or(false);
    if repo_matches {
        return true;
    }

    [
        skill.directory.as_str(),
        skill.name.as_str(),
        skill
            .id
            .split_once(':')
            .map(|(_, slug)| slug)
            .unwrap_or(skill.id.as_str()),
    ]
    .iter()
    .any(|candidate| candidate.to_lowercase().starts_with("baoyu-"))
}

fn standalone_skill_package(skill: &InstalledSkill) -> CapabilityPackage {
    CapabilityPackage {
        id: format!("skill:{}", skill.id),
        package_type: CapabilityPackageType::Standalone,
        name: skill.name.clone(),
        vendor: skill.repo_owner.clone(),
        summary: skill
            .description
            .clone()
            .unwrap_or_else(|| "Standalone Skill".to_string()),
        source: PackageSource {
            kind: "installed-skill".to_string(),
            location: skill
                .repo_owner
                .as_ref()
                .zip(skill.repo_name.as_ref())
                .map(|(owner, name)| format!("{owner}/{name}"))
                .unwrap_or_else(|| skill.directory.clone()),
            update_strategy: skill
                .repo_owner
                .as_ref()
                .map(|_| "github".to_string())
                .unwrap_or_else(|| "manual".to_string()),
            repo_owner: skill.repo_owner.clone(),
            repo_name: skill.repo_name.clone(),
            repo_branch: skill.repo_branch.clone(),
            readme_url: skill.readme_url.clone(),
        },
        components: PackageComponents {
            cli: Vec::new(),
            skills: vec![package_component(
                "skill",
                &skill.id,
                &skill.name,
                true,
                true,
                "installed",
                Some(&skill.directory),
            )],
            mcp: Vec::new(),
            agents: Vec::new(),
        },
        config_schema: Vec::new(),
        installed: true,
        lifecycle: lifecycle_from_skill(Some(skill)),
    }
}

fn lark_capability_package(skills: &[InstalledSkill], agents: &[LocalAgent]) -> CapabilityPackage {
    let skill_ids = [
        "lark-doc",
        "lark-base",
        "lark-sheets",
        "lark-wiki",
        "lark-markdown",
        "lark-shared",
    ];
    let skill_components = skill_ids
        .iter()
        .map(|id| {
            let installed = skills
                .iter()
                .find(|skill| skill_matches_component(skill, id));
            package_component(
                "skill",
                id,
                &title_from_slug(id),
                true,
                installed.is_some(),
                if installed.is_some() {
                    "installed"
                } else {
                    "available"
                },
                installed.map(|skill| skill.directory.as_str()),
            )
        })
        .collect::<Vec<_>>();
    let agent_id = "lark-office-assistant";
    let agent_installed = agents.iter().any(|agent| {
        agent.id.eq_ignore_ascii_case(agent_id) || agent.name.eq_ignore_ascii_case(agent_id)
    });
    let lark_cli_installed = command_exists("lark-cli") || command_exists("lark");
    let package_installed = lark_cli_installed
        || agent_installed
        || skill_components.iter().any(|skill| skill.installed);

    CapabilityPackage {
        id: "pkg:lark".to_string(),
        package_type: CapabilityPackageType::Composite,
        name: "Feishu / Lark".to_string(),
        vendor: Some("ByteDance".to_string()),
        summary: "Composite office package: CLI + Skills + Agent + Keychain config.".to_string(),
        source: PackageSource {
            kind: "builtin".to_string(),
            location: "popskill/builtin/lark".to_string(),
            update_strategy: "manual".to_string(),
            repo_owner: Some("larksuite".to_string()),
            repo_name: Some("cli".to_string()),
            repo_branch: Some("main".to_string()),
            readme_url: Some("https://github.com/larksuite/cli".to_string()),
        },
        components: PackageComponents {
            cli: vec![package_component(
                "cli",
                "lark-cli",
                "lark-cli",
                true,
                lark_cli_installed,
                if lark_cli_installed {
                    "detected"
                } else {
                    "declared"
                },
                None,
            )],
            skills: skill_components,
            mcp: vec![package_component(
                "mcp",
                "lark-openapi-mcp",
                "Lark OpenAPI MCP",
                false,
                false,
                "registry-reference",
                Some("anthropic-mcp-registry/bytedance/lark-openapi-mcp"),
            )],
            agents: vec![package_component(
                "agent",
                agent_id,
                "Lark Office Assistant",
                false,
                agent_installed,
                if agent_installed { "installed" } else { "stub" },
                Some("~/.claude/agents/lark-office-assistant.md"),
            )],
        },
        config_schema: vec![
            config_field("lark.app_id", "App ID", true, true),
            config_field("lark.app_secret", "App Secret", true, true),
        ],
        installed: package_installed,
        lifecycle: lifecycle_from_skills(skills.iter().filter(|skill| {
            skill_ids
                .iter()
                .any(|id| skill_matches_component(skill, id))
        })),
    }
}

fn pdf_capability_package(skills: &[InstalledSkill]) -> CapabilityPackage {
    let skill_id = "pdf-merge-split";
    let installed = skills
        .iter()
        .find(|skill| skill_matches_component(skill, skill_id));
    CapabilityPackage {
        id: "pkg:pdf".to_string(),
        package_type: CapabilityPackageType::Standalone,
        name: "PDF".to_string(),
        vendor: None,
        summary: "Standalone PDF skill package for merge, split, and document cleanup flows."
            .to_string(),
        source: PackageSource {
            kind: "builtin".to_string(),
            location: "popskill/builtin/pdf".to_string(),
            update_strategy: "manual".to_string(),
            repo_owner: None,
            repo_name: None,
            repo_branch: None,
            readme_url: None,
        },
        components: PackageComponents {
            cli: Vec::new(),
            skills: vec![package_component(
                "skill",
                skill_id,
                "PDF Merge Split",
                true,
                installed.is_some(),
                if installed.is_some() {
                    "installed"
                } else {
                    "available"
                },
                installed.map(|skill| skill.directory.as_str()),
            )],
            mcp: Vec::new(),
            agents: Vec::new(),
        },
        config_schema: Vec::new(),
        installed: installed.is_some(),
        lifecycle: lifecycle_from_skill(installed),
    }
}

fn lifecycle_from_skill(skill: Option<&InstalledSkill>) -> PackageLifecycle {
    let Some(skill) = skill else {
        return PackageLifecycle::default();
    };

    PackageLifecycle {
        installed_at: (skill.installed_at > 0).then_some(skill.installed_at),
        updated_at: (skill.updated_at > 0).then_some(skill.updated_at),
        content_hash: skill
            .content_hash
            .clone()
            .filter(|hash| !hash.trim().is_empty()),
    }
}

fn lifecycle_from_skills<'a>(
    skills: impl IntoIterator<Item = &'a InstalledSkill>,
) -> PackageLifecycle {
    let mut installed_at = None;
    let mut updated_at = None;

    for skill in skills {
        if skill.installed_at > 0 {
            installed_at = Some(installed_at.map_or(skill.installed_at, |current: i64| {
                current.max(skill.installed_at)
            }));
        }
        if skill.updated_at > 0 {
            updated_at = Some(updated_at.map_or(skill.updated_at, |current: i64| {
                current.max(skill.updated_at)
            }));
        }
    }

    PackageLifecycle {
        installed_at,
        updated_at,
        content_hash: None,
    }
}

fn skill_matches_component(skill: &InstalledSkill, component_id: &str) -> bool {
    [
        skill.id.as_str(),
        skill.name.as_str(),
        skill.directory.as_str(),
    ]
    .iter()
    .any(|candidate| candidate.eq_ignore_ascii_case(component_id))
}

fn package_component(
    kind: &str,
    id: &str,
    name: &str,
    required: bool,
    installed: bool,
    status: &str,
    location: Option<&str>,
) -> PackageComponent {
    PackageComponent {
        id: id.to_string(),
        name: name.to_string(),
        kind: kind.to_string(),
        required,
        installed,
        status: status.to_string(),
        location: location.map(str::to_string),
    }
}

fn config_field(id: &str, label: &str, required: bool, secret: bool) -> ConfigField {
    ConfigField {
        id: id.to_string(),
        label: label.to_string(),
        required,
        secret,
        storage: if secret { "keychain" } else { "local" }.to_string(),
    }
}

fn build_package_install_result(package: &CapabilityPackage) -> PackageInstallResult {
    let steps = match package.package_type {
        CapabilityPackageType::Composite => vec![
            "inspectDeclaredComponents".to_string(),
            "verifyRequiredConfig".to_string(),
            "installMissingSkillsWithExistingInstallPlan".to_string(),
            "runAgentShieldForSkillComponents".to_string(),
            "leaveCliAndMcpAsExplicitUserDependencies".to_string(),
        ],
        CapabilityPackageType::Standalone => vec![
            "resolveStandaloneSkill".to_string(),
            "installWithExistingSkillInstallFlow".to_string(),
            "runAgentShield".to_string(),
        ],
    };

    PackageInstallResult {
        package_id: package.id.clone(),
        status: "preview".to_string(),
        summary: "Package install is modeled and read-only in this v0.3 self-use build."
            .to_string(),
        steps,
    }
}

fn build_package_config_result(
    package: &CapabilityPackage,
    key: &str,
    value_env: Option<String>,
) -> Result<PackageConfigResult> {
    let key = normalize_required("package config key", key)?;
    let field = package
        .config_schema
        .iter()
        .find(|field| field.id == key)
        .with_context(|| format!("config key '{key}' is not declared by {}", package.id))?;

    if field.secret {
        let value_env = value_env
            .as_deref()
            .context("secret package config values must be passed with --value-env")?;
        let _ = read_optional_env_secret("package config value env", Some(value_env.to_string()))?;
    }

    Ok(PackageConfigResult {
        package_id: package.id.clone(),
        key,
        storage: field.storage.clone(),
        status: "planned".to_string(),
        message: "Package config preview succeeded; no secret was written in this build."
            .to_string(),
    })
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct EnrichedInstalledSkill {
    #[serde(flatten)]
    inner: InstalledSkill,
    #[serde(skip_serializing_if = "Option::is_none")]
    capability_summary: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    trigger_scenarios: Vec<String>,
}

fn enrich_installed_skill(skill: InstalledSkill) -> EnrichedInstalledSkill {
    // CC Switch already parses SKILL.md frontmatter description (including YAML
    // multi-line scalars), so reuse it for capability_summary. Only read SKILL.md
    // ourselves to extract the `triggers:` field, which CC Switch does not expose.
    let trigger_scenarios = installed_skill_dir(&skill)
        .ok()
        .and_then(|dir| std::fs::read_to_string(dir.join("SKILL.md")).ok())
        .map(|content| parse_skill_triggers(&content))
        .unwrap_or_default();

    let capability_summary = skill.description.as_deref().and_then(first_sentence_of);

    EnrichedInstalledSkill {
        inner: skill,
        capability_summary,
        trigger_scenarios,
    }
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

fn parse_agent_markdown(content: &str) -> ParsedAgentMarkdown {
    let Some((frontmatter, body)) = split_frontmatter(content) else {
        return ParsedAgentMarkdown {
            name: None,
            description: first_markdown_paragraph(content),
            tools: Vec::new(),
            model: None,
        };
    };

    let mut parsed = ParsedAgentMarkdown::default();
    for line in frontmatter.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };

        let key = key.trim();
        let value = unquote_frontmatter_value(value.trim());
        if value.is_empty() {
            continue;
        }

        match key {
            "name" => parsed.name = Some(value),
            "description" => parsed.description = Some(value),
            "tools" => parsed.tools = split_agent_tools(&value),
            "model" => parsed.model = Some(value),
            _ => {}
        }
    }

    if parsed.description.is_none() {
        parsed.description = first_markdown_paragraph(body);
    }

    parsed
}

fn parse_skill_triggers(content: &str) -> Vec<String> {
    let Some((frontmatter, _body)) = split_frontmatter(content) else {
        return Vec::new();
    };

    let mut triggers: Vec<String> = Vec::new();
    let mut in_triggers_block = false;

    for line in frontmatter.lines() {
        if in_triggers_block {
            let trimmed = line.trim_start();
            if let Some(item) = trimmed.strip_prefix("- ") {
                let cleaned = unquote_frontmatter_value(item.trim());
                if !cleaned.is_empty() {
                    triggers.push(cleaned);
                }
                continue;
            }
            in_triggers_block = false;
        }

        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim();
        let value = unquote_frontmatter_value(value.trim());

        if key == "triggers" {
            if value.is_empty() {
                in_triggers_block = true;
            } else {
                let inline = value.trim_start_matches('[').trim_end_matches(']');
                for item in inline.split(',') {
                    let cleaned = unquote_frontmatter_value(item.trim());
                    if !cleaned.is_empty() {
                        triggers.push(cleaned);
                    }
                }
            }
        }
    }

    triggers
}

fn first_sentence_of(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let cut = trimmed.find(['。', '.', ';', '；', '!', '！', '?', '？']);
    let summary = match cut {
        Some(index) => &trimmed[..index],
        None => trimmed,
    };
    let summary = summary.trim();
    if summary.is_empty() {
        None
    } else {
        let limited: String = summary.chars().take(120).collect();
        Some(limited)
    }
}

fn split_frontmatter(content: &str) -> Option<(&str, &str)> {
    let content = content.strip_prefix("---")?;
    let content = content
        .strip_prefix("\r\n")
        .or_else(|| content.strip_prefix('\n'))?;
    let delimiter = content
        .find("\n---\n")
        .map(|index| (index, 5))
        .or_else(|| content.find("\n---\r\n").map(|index| (index, 6)))?;
    Some((
        &content[..delimiter.0],
        &content[delimiter.0 + delimiter.1..],
    ))
}

fn unquote_frontmatter_value(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.len() >= 2 {
        let bytes = trimmed.as_bytes();
        if (bytes[0] == b'"' && bytes[trimmed.len() - 1] == b'"')
            || (bytes[0] == b'\'' && bytes[trimmed.len() - 1] == b'\'')
        {
            return trimmed[1..trimmed.len() - 1].to_string();
        }
    }
    trimmed.to_string()
}

fn split_agent_tools(value: &str) -> Vec<String> {
    let trimmed = value.trim().trim_start_matches('[').trim_end_matches(']');
    trimmed
        .split(',')
        .map(unquote_frontmatter_value)
        .map(|tool| tool.trim().to_string())
        .filter(|tool| !tool.is_empty())
        .collect()
}

fn first_markdown_paragraph(content: &str) -> Option<String> {
    content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| !line.starts_with('#'))
        .filter(|line| !line.starts_with("---"))
        .find(|line| {
            !line.starts_with("name:")
                && !line.starts_with("description:")
                && !line.starts_with("tools:")
                && !line.starts_with("model:")
        })
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

fn webdav_sync_plan_from_settings_value(settings: serde_json::Value) -> serde_json::Value {
    let status = webdav_status_from_settings_value(settings);
    let configured = status
        .get("configured")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let enabled = status
        .get("enabled")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let (readiness, summary) = if !configured {
        (
            "unconfigured",
            "Save WebDAV settings before manual sync can be evaluated.",
        )
    } else if !enabled {
        (
            "disabled",
            "Enable WebDAV sync before manual upload/download can be evaluated.",
        )
    } else {
        (
            "blocked-by-cc-switch-boundary",
            "Remote snapshot lookup is available, but manual upload/download is not exposed from the sidecar yet.",
        )
    };

    json!({
        "available": false,
        "readiness": readiness,
        "summary": summary,
        "blockedBy": [
            "CC Switch webdav_sync_upload/webdav_sync_download currently require Tauri State<AppState>.",
            "The underlying WebDAV sync service and settings types are private to the CC Switch submodule.",
            "Popskill does not modify cc-switch/ and does not copy the WebDAV protocol implementation for v0.1."
        ],
        "safeActions": [
            "webdav-status --json",
            "webdav-remote-info --json",
            "webdav-configure --json"
        ],
        "requiresSubmoduleApi": true
    })
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DomainSchema {
    schema_version: u8,
    model_name: &'static str,
    source_kinds: Vec<AssetSourceKind>,
    version_modes: Vec<AssetVersionMode>,
    package_types: Vec<AssetPackageType>,
    component_kinds: Vec<AssetComponentKind>,
    deployment_strategies: Vec<AssetDeploymentStrategy>,
    runtime_transports: Vec<AssetRuntimeTransport>,
    mutation_phases: Vec<AssetMutationPhase>,
    default_strategy_order: Vec<AssetDeploymentStrategy>,
    error_codes: Vec<AppErrorDefinition>,
    invariants: Vec<&'static str>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetPackageManifest {
    schema_version: u8,
    id: String,
    display_name: String,
    package_type: AssetPackageType,
    source: AssetSourceRef,
    components: Vec<AssetComponentManifest>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetSourceRef {
    id: String,
    kind: AssetSourceKind,
    locator: String,
    version_mode: AssetVersionMode,
    resolved_version: Option<String>,
    content_hash: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetComponentManifest {
    id: String,
    kind: AssetComponentKind,
    display_name: String,
    entry: String,
    runtime: Option<AssetRuntimeSpec>,
    compatibility: Vec<AssetTargetCompatibility>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetRuntimeSpec {
    command: String,
    args: Vec<String>,
    env_refs: Vec<String>,
    transport: AssetRuntimeTransport,
    healthcheck: Option<AssetHealthcheck>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetHealthcheck {
    kind: String,
    value: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetTargetCompatibility {
    target_id: String,
    supported: bool,
    preferred_strategy: Option<AssetDeploymentStrategy>,
    notes: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetDeploymentRecord {
    package_id: String,
    component_id: String,
    target_id: String,
    strategy: AssetDeploymentStrategy,
    target_path: String,
    status: String,
    applied_hash: Option<String>,
    applied_at: Option<i64>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct AssetSnapshotRecord {
    id: String,
    before_paths: Vec<String>,
    after_paths: Vec<String>,
    backup_path: String,
    created_at: i64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetSourceKind {
    Local,
    Git,
    Zip,
    Registry,
    Mcp,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetVersionMode {
    Pinned,
    Floating,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetPackageType {
    Standalone,
    Composite,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetComponentKind {
    Skill,
    Cli,
    McpServer,
    Agent,
    Rule,
    Prompt,
    Config,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetDeploymentStrategy {
    Copy,
    Symlink,
    Wrapper,
    ConfigPatch,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetRuntimeTransport {
    Stdio,
    StreamableHttp,
    None,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AssetMutationPhase {
    Plan,
    Snapshot,
    Apply,
    Verify,
    Commit,
    Rollback,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AppErrorDefinition {
    code: &'static str,
    retryable: bool,
    rollback_relevant: bool,
    description: &'static str,
}

fn domain_schema() -> DomainSchema {
    DomainSchema {
        schema_version: 1,
        model_name: "popskill.asset-control-plane",
        source_kinds: vec![
            AssetSourceKind::Local,
            AssetSourceKind::Git,
            AssetSourceKind::Zip,
            AssetSourceKind::Registry,
            AssetSourceKind::Mcp,
        ],
        version_modes: vec![AssetVersionMode::Pinned, AssetVersionMode::Floating],
        package_types: vec![AssetPackageType::Standalone, AssetPackageType::Composite],
        component_kinds: vec![
            AssetComponentKind::Skill,
            AssetComponentKind::Cli,
            AssetComponentKind::McpServer,
            AssetComponentKind::Agent,
            AssetComponentKind::Rule,
            AssetComponentKind::Prompt,
            AssetComponentKind::Config,
        ],
        deployment_strategies: vec![
            AssetDeploymentStrategy::Copy,
            AssetDeploymentStrategy::Symlink,
            AssetDeploymentStrategy::Wrapper,
            AssetDeploymentStrategy::ConfigPatch,
        ],
        runtime_transports: vec![
            AssetRuntimeTransport::Stdio,
            AssetRuntimeTransport::StreamableHttp,
            AssetRuntimeTransport::None,
        ],
        mutation_phases: vec![
            AssetMutationPhase::Plan,
            AssetMutationPhase::Snapshot,
            AssetMutationPhase::Apply,
            AssetMutationPhase::Verify,
            AssetMutationPhase::Commit,
            AssetMutationPhase::Rollback,
        ],
        default_strategy_order: vec![
            AssetDeploymentStrategy::Copy,
            AssetDeploymentStrategy::ConfigPatch,
            AssetDeploymentStrategy::Wrapper,
            AssetDeploymentStrategy::Symlink,
        ],
        error_codes: vec![
            AppErrorDefinition {
                code: "E_TARGET_NOT_FOUND",
                retryable: false,
                rollback_relevant: false,
                description: "The requested deployment target is not registered or not detected.",
            },
            AppErrorDefinition {
                code: "E_STRATEGY_UNSUPPORTED",
                retryable: false,
                rollback_relevant: false,
                description: "The target does not support the requested deployment strategy.",
            },
            AppErrorDefinition {
                code: "E_CONFIG_MERGE_CONFLICT",
                retryable: false,
                rollback_relevant: true,
                description: "A third-party config file could not be merged without risking user data.",
            },
            AppErrorDefinition {
                code: "E_SECRET_UNAVAILABLE",
                retryable: true,
                rollback_relevant: false,
                description: "A required secret reference could not be resolved from the OS secret store.",
            },
            AppErrorDefinition {
                code: "E_PROCESS_TIMEOUT",
                retryable: true,
                rollback_relevant: true,
                description: "A managed runtime process did not become healthy before its timeout.",
            },
            AppErrorDefinition {
                code: "E_VERIFY_FAILED",
                retryable: true,
                rollback_relevant: true,
                description: "Apply finished but post-apply verification failed.",
            },
            AppErrorDefinition {
                code: "E_ROLLBACK_FAILED",
                retryable: false,
                rollback_relevant: true,
                description: "Rollback was attempted but one or more restore steps failed.",
            },
        ],
        invariants: vec![
            "SSOT lives in Popskill-controlled state; target folders are projections.",
            "Symlink is a target-specific deployment strategy, never the only source of truth.",
            "Mutating operations run plan -> snapshot -> apply -> verify -> commit, with rollback on apply or verify failure.",
            "Third-party configuration writes must use merge/patch; whole-file overwrite is forbidden.",
            "UI code must call typed sidecar commands and must not directly mutate third-party files.",
            "Secrets are stored as OS secret-store references, not in SQLite, JSON, logs, or argv.",
        ],
    }
}

#[derive(Default)]
struct ParsedAgentMarkdown {
    name: Option<String>,
    description: Option<String>,
    tools: Vec<String>,
    model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalAgent {
    id: String,
    name: String,
    description: String,
    file_name: String,
    path: String,
    category: String,
    tools: Vec<String>,
    model: Option<String>,
    last_modified_at: Option<i64>,
    size_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentTarget {
    id: String,
    name: String,
    scope: String,
    format: String,
    paths: Vec<String>,
    detected: bool,
    source: String,
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubTreeResponse {
    tree: Vec<GitHubTreeEntry>,
}

#[derive(Debug, Deserialize)]
struct GitHubTreeEntry {
    path: String,
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CatalogAgent {
    id: String,
    name: String,
    description: String,
    path: String,
    category: String,
    repo_owner: String,
    repo_name: String,
    repo_branch: String,
    readme_url: String,
    raw_url: String,
    tools: Vec<String>,
    model: Option<String>,
    source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentInstallPlan {
    agent_id: String,
    name: String,
    target_id: String,
    target_name: String,
    target_format: String,
    source: AgentInstallSource,
    writes: Vec<String>,
    conflict: Option<AgentInstallConflict>,
    requires_conversion: bool,
    steps: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentInstallSource {
    repo_owner: String,
    repo_name: String,
    repo_branch: String,
    path: String,
    raw_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentInstallConflict {
    paths: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum CapabilityPackageType {
    Composite,
    Standalone,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityPackage {
    id: String,
    #[serde(rename = "type")]
    package_type: CapabilityPackageType,
    name: String,
    vendor: Option<String>,
    summary: String,
    source: PackageSource,
    components: PackageComponents,
    config_schema: Vec<ConfigField>,
    installed: bool,
    #[serde(default)]
    lifecycle: PackageLifecycle,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PackageSource {
    kind: String,
    location: String,
    update_strategy: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_owner: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_branch: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    readme_url: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PackageLifecycle {
    #[serde(skip_serializing_if = "Option::is_none")]
    installed_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    updated_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    content_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PackageComponents {
    cli: Vec<PackageComponent>,
    skills: Vec<PackageComponent>,
    mcp: Vec<PackageComponent>,
    agents: Vec<PackageComponent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PackageComponent {
    id: String,
    name: String,
    kind: String,
    required: bool,
    installed: bool,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    location: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigField {
    id: String,
    label: String,
    required: bool,
    secret: bool,
    storage: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PackageInstallResult {
    package_id: String,
    status: String,
    summary: String,
    steps: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PackageConfigResult {
    package_id: String,
    key: String,
    storage: String,
    status: String,
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
    fn webdav_sync_plan_reports_unconfigured_state() {
        let plan = webdav_sync_plan_from_settings_value(json!({}));

        assert_eq!(plan["available"], false);
        assert_eq!(plan["readiness"], "unconfigured");
        assert_eq!(plan["requiresSubmoduleApi"], true);
    }

    #[test]
    fn webdav_sync_plan_explains_blocked_manual_sync() {
        let plan = webdav_sync_plan_from_settings_value(json!({
            "webdavSync": {
                "enabled": true,
                "autoSync": false,
                "baseUrl": "https://dav.example.com",
                "username": "demo",
                "password": "secret",
                "remoteRoot": "cc-switch-sync",
                "profile": "default"
            }
        }));

        assert_eq!(plan["available"], false);
        assert_eq!(plan["readiness"], "blocked-by-cc-switch-boundary");
        assert!(
            plan["summary"]
                .as_str()
                .unwrap()
                .contains("manual upload/download")
        );
        assert!(plan["blockedBy"].as_array().unwrap().len() >= 2);
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

    #[test]
    fn parse_agent_markdown_reads_frontmatter_fields() {
        let parsed = parse_agent_markdown(
            r#"---
name: frontend-developer
description: Build polished SwiftUI interfaces.
tools: Read, Write, Bash
model: sonnet
---
# Frontend Developer

Body fallback should not win.
"#,
        );

        assert_eq!(parsed.name.as_deref(), Some("frontend-developer"));
        assert_eq!(
            parsed.description.as_deref(),
            Some("Build polished SwiftUI interfaces.")
        );
        assert_eq!(parsed.tools, vec!["Read", "Write", "Bash"]);
        assert_eq!(parsed.model.as_deref(), Some("sonnet"));
    }

    #[test]
    fn parse_agent_markdown_falls_back_to_first_paragraph() {
        let parsed = parse_agent_markdown(
            r#"# Product Strategist

Turns fuzzy product ideas into crisp release plans.
"#,
        );

        assert_eq!(parsed.name, None);
        assert_eq!(
            parsed.description.as_deref(),
            Some("Turns fuzzy product ideas into crisp release plans.")
        );
    }

    #[test]
    fn local_agent_from_markdown_infers_category_and_title() {
        let root = Path::new("/tmp/agents");
        let path = root.join("engineering/backend-architect.md");
        let metadata = fs::metadata(".").unwrap();

        let agent = local_agent_from_markdown(root, &path, "No frontmatter body.", &metadata)
            .expect("agent should parse");

        assert_eq!(agent.id, "engineering/backend-architect");
        assert_eq!(agent.name, "Backend Architect");
        assert_eq!(agent.category, "engineering");
        assert_eq!(agent.file_name, "backend-architect.md");
    }

    #[test]
    fn agent_targets_include_agency_agents_tool_matrix() {
        let targets = agent_targets_for_paths(
            Path::new("/Users/example"),
            Path::new("/Users/example/project"),
            |_| false,
        );

        assert_eq!(targets.len(), 11);
        assert_eq!(targets[0].id, "claude-code");
        assert_eq!(targets[0].paths, vec!["/Users/example/.claude/agents"]);

        let qwen = targets
            .iter()
            .find(|target| target.id == "qwen")
            .expect("qwen target should exist");
        assert_eq!(qwen.scope, "user/project");
        assert!(
            qwen.paths
                .contains(&"/Users/example/.qwen/agents".to_string())
        );
        assert!(
            qwen.paths
                .contains(&"/Users/example/project/.qwen/agents".to_string())
        );

        let kimi = targets
            .iter()
            .find(|target| target.id == "kimi")
            .expect("kimi target should exist");
        assert_eq!(kimi.format, "agent-yaml");
        assert_eq!(kimi.paths, vec!["/Users/example/.config/kimi/agents"]);
    }

    #[test]
    fn catalog_agent_from_tree_path_builds_agency_agents_payload() {
        let agent = catalog_agent_from_tree_path("marketing/xiaohongshu-specialist.md", "blob")
            .expect("agent should parse");

        assert_eq!(
            agent.id,
            "msitarzewski/agency-agents:marketing/xiaohongshu-specialist"
        );
        assert_eq!(agent.name, "Xiaohongshu Specialist");
        assert_eq!(agent.category, "marketing");
        assert_eq!(
            agent.readme_url,
            "https://github.com/msitarzewski/agency-agents/blob/main/marketing/xiaohongshu-specialist.md"
        );
        assert!(agent.raw_url.contains("raw.githubusercontent.com"));
    }

    #[test]
    fn catalog_agent_from_tree_path_rejects_non_agent_markdown() {
        assert!(catalog_agent_from_tree_path("README.md", "blob").is_none());
        assert!(catalog_agent_from_tree_path("examples/example.md", "blob").is_none());
        assert!(
            catalog_agent_from_tree_path("engineering/backend-developer.txt", "blob").is_none()
        );
        assert!(catalog_agent_from_tree_path("engineering/nested/agent.md", "blob").is_none());
        assert!(catalog_agent_from_tree_path("engineering/backend-developer.md", "tree").is_none());
    }

    #[test]
    fn agency_agent_from_key_accepts_repo_prefixed_and_plain_paths() {
        let prefixed = agency_agent_from_key(
            "msitarzewski/agency-agents:marketing/marketing-xiaohongshu-specialist",
        )
        .expect("prefixed key should parse");
        let plain = agency_agent_from_key("marketing/marketing-xiaohongshu-specialist.md")
            .expect("plain path should parse");

        assert_eq!(
            prefixed.path,
            "marketing/marketing-xiaohongshu-specialist.md"
        );
        assert_eq!(plain.id, prefixed.id);
    }

    #[test]
    fn target_destination_paths_append_markdown_to_directory_targets() {
        let target = AgentTarget {
            id: "claude-code".to_string(),
            name: "Claude Code".to_string(),
            scope: "user".to_string(),
            format: "markdown-agent".to_string(),
            paths: vec!["/Users/example/.claude/agents".to_string()],
            detected: true,
            source: "agency-agents".to_string(),
            note: None,
        };

        let writes = target_destination_paths(&target, "marketing/demo-agent.md")
            .expect("writes should plan");

        assert_eq!(writes, vec!["/Users/example/.claude/agents/demo-agent.md"]);
    }

    #[test]
    fn target_destination_paths_preserve_file_targets() {
        let target = AgentTarget {
            id: "aider".to_string(),
            name: "Aider".to_string(),
            scope: "project".to_string(),
            format: "conventions".to_string(),
            paths: vec!["/Users/example/project/CONVENTIONS.md".to_string()],
            detected: false,
            source: "agency-agents".to_string(),
            note: None,
        };

        let writes = target_destination_paths(&target, "engineering/backend.md")
            .expect("writes should plan");

        assert_eq!(writes, vec!["/Users/example/project/CONVENTIONS.md"]);
    }

    #[test]
    fn standalone_skill_package_wraps_installed_skill() {
        let skill = installed_skill_fixture("owner/repo:demo-skill");
        let package = standalone_skill_package(&skill);

        assert_eq!(package.id, "skill:owner/repo:demo-skill");
        assert_eq!(package.package_type, CapabilityPackageType::Standalone);
        assert_eq!(package.components.skills.len(), 1);
        assert_eq!(package.components.skills[0].kind, "skill");
        assert!(package.installed);
    }

    #[test]
    fn lark_capability_package_contains_composite_tree_and_keychain_config() {
        let skills = vec![installed_skill_fixture("lark-doc")];
        let agents = vec![LocalAgent {
            id: "lark-office-assistant".to_string(),
            name: "Lark Office Assistant".to_string(),
            description: "Demo agent".to_string(),
            file_name: "lark-office-assistant.md".to_string(),
            path: "/Users/example/.claude/agents/lark-office-assistant.md".to_string(),
            category: "office".to_string(),
            tools: vec!["Read".to_string(), "Write".to_string()],
            model: None,
            last_modified_at: Some(1),
            size_bytes: 128,
        }];

        let package = lark_capability_package(&skills, &agents);

        assert_eq!(package.id, "pkg:lark");
        assert_eq!(package.package_type, CapabilityPackageType::Composite);
        assert_eq!(package.components.skills.len(), 6);
        assert!(package.components.skills[0].installed);
        assert_eq!(package.components.agents[0].status, "installed");
        assert_eq!(package.config_schema.len(), 2);
        assert!(
            package
                .config_schema
                .iter()
                .all(|field| field.storage == "keychain")
        );
    }

    #[test]
    fn baoyu_capability_package_groups_repo_and_local_baoyu_skills() {
        let mut repo_skill =
            installed_skill_fixture("jimliu/baoyu-skills:baoyu-article-illustrator");
        repo_skill.name = "baoyu-article-illustrator".to_string();
        repo_skill.directory = "baoyu-article-illustrator".to_string();
        repo_skill.repo_owner = Some("JimLiu".to_string());
        repo_skill.repo_name = Some("baoyu-skills".to_string());
        repo_skill.repo_branch = Some("main".to_string());

        let mut local_skill = installed_skill_fixture("local:baoyu-imagine");
        local_skill.name = "baoyu-imagine".to_string();
        local_skill.directory = "baoyu-imagine".to_string();
        local_skill.repo_owner = None;
        local_skill.repo_name = None;
        local_skill.repo_branch = None;

        let skills = vec![repo_skill, local_skill];
        let package = baoyu_capability_package(&skills).expect("baoyu package should be grouped");

        assert_eq!(package.id, "pkg:jimliu/baoyu-skills");
        assert_eq!(package.package_type, CapabilityPackageType::Composite);
        assert_eq!(package.source.kind, "github");
        assert_eq!(package.source.location, "jimliu/baoyu-skills");
        assert_eq!(package.components.skills.len(), 2);
        assert_eq!(
            package
                .components
                .skills
                .iter()
                .map(|component| component.location.as_deref().unwrap_or(""))
                .collect::<Vec<_>>(),
            vec!["baoyu-article-illustrator", "baoyu-imagine"]
        );
    }

    #[test]
    fn baoyu_package_detection_uses_repo_metadata_before_slug_fallback() {
        let mut repo_skill = installed_skill_fixture("jimliu/baoyu-skills:custom-name");
        repo_skill.name = "custom-name".to_string();
        repo_skill.directory = "custom-name".to_string();
        repo_skill.repo_owner = Some("jimliu".to_string());
        repo_skill.repo_name = Some("baoyu-skills".to_string());

        let mut local_baoyu = installed_skill_fixture("local:baoyu-diagram");
        local_baoyu.name = "baoyu-diagram".to_string();
        local_baoyu.directory = "baoyu-diagram".to_string();
        local_baoyu.repo_owner = None;
        local_baoyu.repo_name = None;

        let unrelated = installed_skill_fixture("owner/repo:demo-skill");

        assert!(is_baoyu_package_skill(&repo_skill));
        assert!(is_baoyu_package_skill(&local_baoyu));
        assert!(!is_baoyu_package_skill(&unrelated));
    }

    #[test]
    fn pdf_capability_package_is_builtin_standalone() {
        let package = pdf_capability_package(&[]);

        assert_eq!(package.id, "pkg:pdf");
        assert_eq!(package.package_type, CapabilityPackageType::Standalone);
        assert_eq!(package.source.kind, "builtin");
        assert_eq!(package.components.skills[0].id, "pdf-merge-split");
        assert!(!package.installed);
    }

    #[test]
    fn domain_schema_declares_asset_control_plane_primitives() {
        let schema = domain_schema();

        assert_eq!(schema.schema_version, 1);
        assert_eq!(schema.model_name, "popskill.asset-control-plane");
        assert!(schema.component_kinds.contains(&AssetComponentKind::Skill));
        assert!(
            schema
                .component_kinds
                .contains(&AssetComponentKind::McpServer)
        );
        assert!(schema.component_kinds.contains(&AssetComponentKind::Agent));
        assert!(
            schema
                .deployment_strategies
                .contains(&AssetDeploymentStrategy::Copy)
        );
        assert!(
            schema
                .deployment_strategies
                .contains(&AssetDeploymentStrategy::ConfigPatch)
        );
        assert_eq!(
            schema.default_strategy_order.last(),
            Some(&AssetDeploymentStrategy::Symlink)
        );
        assert!(
            schema.error_codes.iter().any(|error| {
                error.code == "E_CONFIG_MERGE_CONFLICT" && error.rollback_relevant
            })
        );
        assert!(schema.invariants.iter().any(|invariant| {
            invariant.contains("Symlink is a target-specific deployment strategy")
        }));
    }

    fn stub_fixture(id: &str, stubbed_at: i64) -> StubbedSkill {
        StubbedSkill {
            skill: installed_skill_fixture(id),
            backup_id: format!("backup-{id}"),
            backup_path: format!("/tmp/backup-{id}"),
            stubbed_at,
        }
    }

    fn installed_skill_fixture(id: &str) -> InstalledSkill {
        InstalledSkill {
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
