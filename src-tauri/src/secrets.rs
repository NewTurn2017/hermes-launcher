//! OS-native secret storage (Windows Credential Manager / macOS Keychain).
//!
//! `KeyringStore` is the real backend (via the `keyring` crate). Cross-call
//! persistence is keyring's responsibility and is verified on real
//! Windows/macOS; here we unit-test our own error-mapping (NoEntry -> None /
//! Ok) against keyring's in-memory mock, plus the round-trip contract against
//! an in-memory `MemoryStore`.
use keyring::Entry;

const SERVICE: &str = "hermes-launcher";

pub trait SecretStore {
    fn store(&self, key: &str, value: &str) -> Result<(), String>;
    fn retrieve(&self, key: &str) -> Result<Option<String>, String>;
    fn delete(&self, key: &str) -> Result<(), String>;
}

/// Real backend: Windows Credential Manager / macOS Keychain.
pub struct KeyringStore;

impl SecretStore for KeyringStore {
    fn store(&self, key: &str, value: &str) -> Result<(), String> {
        Entry::new(SERVICE, key)
            .map_err(|e| e.to_string())?
            .set_password(value)
            .map_err(|e| e.to_string())
    }

    fn retrieve(&self, key: &str) -> Result<Option<String>, String> {
        let entry = Entry::new(SERVICE, key).map_err(|e| e.to_string())?;
        match entry.get_password() {
            Ok(v) => Ok(Some(v)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }

    fn delete(&self, key: &str) -> Result<(), String> {
        let entry = Entry::new(SERVICE, key).map_err(|e| e.to_string())?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Mutex, Once};

    static INIT: Once = Once::new();
    fn use_mock() {
        // In-memory keyring: never touches the real Keychain (no prompts).
        INIT.call_once(|| {
            keyring::set_default_credential_builder(keyring::mock::default_credential_builder());
        });
    }

    /// In-memory store used to test the SecretStore round-trip contract.
    struct MemoryStore {
        inner: Mutex<HashMap<String, String>>,
    }
    impl MemoryStore {
        fn new() -> Self {
            MemoryStore { inner: Mutex::new(HashMap::new()) }
        }
    }
    impl SecretStore for MemoryStore {
        fn store(&self, key: &str, value: &str) -> Result<(), String> {
            self.inner.lock().unwrap().insert(key.to_string(), value.to_string());
            Ok(())
        }
        fn retrieve(&self, key: &str) -> Result<Option<String>, String> {
            Ok(self.inner.lock().unwrap().get(key).cloned())
        }
        fn delete(&self, key: &str) -> Result<(), String> {
            self.inner.lock().unwrap().remove(key);
            Ok(())
        }
    }

    #[test]
    fn memory_store_round_trips() {
        let s = MemoryStore::new();
        assert_eq!(s.retrieve("k").unwrap(), None);
        s.store("k", "xoxb-secret").unwrap();
        assert_eq!(s.retrieve("k").unwrap(), Some("xoxb-secret".to_string()));
        s.delete("k").unwrap();
        assert_eq!(s.retrieve("k").unwrap(), None);
    }

    #[test]
    fn keyring_store_missing_key_returns_none() {
        use_mock();
        assert_eq!(KeyringStore.retrieve("never_set_key").unwrap(), None);
    }

    #[test]
    fn keyring_store_delete_missing_is_ok() {
        use_mock();
        assert!(KeyringStore.delete("never_existed_key").is_ok());
    }
}
