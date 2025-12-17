use crate::utils::base64url::encode;
use crate::utils::hmac256::HmacSha256;
use crate::utils::time_stamp::time_sync;

pub struct CustomJwt {
    secret: String,
    header: String,
    payload: String,
}

impl CustomJwt {
    pub fn new(user_id: &str, user_secret: &str) -> CustomJwt {
        let header = "{\"alg\":\"HS256\",\"sign_type\":\"SIGN\"}".to_string();
        let payload = CustomJwt::jwt_payload(user_id);
        CustomJwt {
            secret: user_secret.to_string(),
            header,
            payload,
        }
    }

    pub fn create_jwt(&self) -> String {
        let encoded_header = encode(self.header.as_bytes());
        let encoded_payload = encode(self.payload.as_bytes());
        let to_sign = format!("{}.{}", encoded_header, encoded_payload);

        let signature_bytes = self.generate_signature(&to_sign);
        let calculated_signature = encode(&signature_bytes);
        format!("{}.{}", to_sign, calculated_signature)
    }

    pub fn verify_jwt(&self, jwt: &str) -> bool {
        let jwt = jwt.trim();

        let parts: Vec<&str> = jwt.split('.').collect();
        if parts.len() != 3 {
            return false;
        }

        let encoded_header = parts[0];
        let encoded_payload = parts[1];
        let signature = parts[2];

        let to_verify = format!("{}.{}", encoded_header, encoded_payload);
        let calculated_signature_bytes = self.generate_signature(&to_verify);
        let calculated_signature = encode(&calculated_signature_bytes);

        calculated_signature == signature
    }

    fn jwt_payload(user_id: &str) -> String {
        let time_now = time_sync(); 
        let exp_time = time_now * 2;
        format!(
            "{{\"api_key\":\"{}\",\"exp\":{},\"timestamp\":{:?}}}",
            user_id, exp_time, time_now
        )
    }

    fn generate_signature(&self, data: &str) -> Vec<u8> {
        let mut mac = HmacSha256::new(self.secret.as_bytes());
        mac.update(data.as_bytes());
        mac.finalize().to_vec()
    }
}