use crate::utils::sha256::Sha256;

pub struct HmacSha256 {
    opad_key: [u8; 64],
    hasher: Sha256,
}

impl HmacSha256 {
    pub fn new(key: &[u8]) -> Self {
        let mut key_block = [0u8; 64];

        if key.len() > 64 {
            let mut sha = Sha256::new();
            sha.update(key);
            let hash = sha.finalize();
            key_block[..32].copy_from_slice(&hash);
        } else {
            key_block[..key.len()].copy_from_slice(key);
        }

        let mut ipad = [0u8; 64];
        let mut opad = [0u8; 64];

        for i in 0..64 {
            ipad[i] = key_block[i] ^ 0x36;
            opad[i] = key_block[i] ^ 0x5c;
        }

        let mut hasher = Sha256::new();
        hasher.update(&ipad);

        HmacSha256 {
            opad_key: opad,
            hasher,
        }
    }

    pub fn update(&mut self, data: &[u8]) {
        self.hasher.update(data);
    }

    pub fn finalize(self) -> [u8; 32] {
        let inner_hash = self.hasher.finalize();

        let mut outer = Sha256::new();
        outer.update(&self.opad_key);
        outer.update(&inner_hash);
        outer.finalize()
    }
}
