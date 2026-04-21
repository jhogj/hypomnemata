from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="HYPO_", env_file=".env", extra="ignore")

    data_dir: Path = Path.home() / "Hypomnemata"
    max_asset_mb: int = 100
    host: str = "127.0.0.1"
    port: int = 8787
    cors_origins: list[str] = ["http://localhost:5173", "http://127.0.0.1:5173"]
    allow_chrome_extension: bool = True

    @property
    def db_path(self) -> Path:
        return self.data_dir / "hypomnemata.db"

    @property
    def assets_dir(self) -> Path:
        return self.data_dir / "assets"

    @property
    def db_url(self) -> str:
        return f"sqlite+aiosqlite:///{self.db_path}"

    @property
    def sync_db_url(self) -> str:
        return f"sqlite:///{self.db_path}"

    def ensure_dirs(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.assets_dir.mkdir(parents=True, exist_ok=True)


settings = Settings()
