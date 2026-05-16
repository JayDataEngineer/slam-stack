#[cfg(feature = "ssr")]
mod imp {
    use sqlx::postgres::PgPool;
    use std::sync::OnceLock;

    static DB: OnceLock<PgPool> = OnceLock::new();

    pub async fn init(url: &str) -> Result<(), sqlx::Error> {
        let pool = PgPool::connect(url).await?;

        sqlx::query(
            "CREATE TABLE IF NOT EXISTS incident (
                id BIGSERIAL PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                severity TEXT NOT NULL DEFAULT 'Medium'
                    CHECK (severity IN ('Critical', 'High', 'Medium', 'Low')),
                status TEXT NOT NULL DEFAULT 'Open'
                    CHECK (status IN ('Open', 'Investigating', 'Contained', 'Resolved')),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )",
        )
        .execute(&pool)
        .await?;

        DB.set(pool)
            .map_err(|_| sqlx::Error::PoolTimedOut)
            .expect("DB already initialized");
        Ok(())
    }

    pub fn get() -> &'static PgPool {
        DB.get().expect("Database not initialized")
    }
}

#[cfg(feature = "ssr")]
pub use imp::*;
