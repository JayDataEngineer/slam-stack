#[cfg(feature = "ssr")]
mod imp {
    use surrealdb::Surreal;
    use std::sync::OnceLock;

    type DbClient = surrealdb::engine::remote::http::Client;
    static DB: OnceLock<Surreal<DbClient>> = OnceLock::new();

    pub async fn init(
        url: &str,
        ns: &str,
        db: &str,
        user: &str,
        pass: &str,
    ) -> surrealdb::Result<()> {
        let client = Surreal::new::<surrealdb::engine::remote::http::Http>(url).await?;
        client
            .signin(surrealdb::opt::auth::Root {
                username: user,
                password: pass,
            })
            .await?;
        client.use_ns(ns).use_db(db).await?;

        // Seed schema
        let _: Vec<serde_json::Value> = client
            .query(
                "DEFINE TABLE IF NOT EXISTS incident SCHEMAFULL;
                 DEFINE FIELD IF NOT EXISTS title ON incident TYPE string;
                 DEFINE FIELD IF NOT EXISTS description ON incident TYPE string;
                 DEFINE FIELD IF NOT EXISTS severity ON incident TYPE string DEFAULT 'Medium';
                 DEFINE FIELD IF NOT EXISTS status ON incident TYPE string DEFAULT 'Open';
                 DEFINE FIELD IF NOT EXISTS created_at ON incident TYPE string;
                 DEFINE FIELD IF NOT EXISTS updated_at ON incident TYPE string;",
            )
            .await?
            .take(0)?;

        DB.set(client)
            .map_err(|_| "DB already initialized")
            .unwrap();
        Ok(())
    }

    pub fn get() -> &'static Surreal<DbClient> {
        DB.get().expect("Database not initialized")
    }
}

#[cfg(feature = "ssr")]
pub use imp::*;
