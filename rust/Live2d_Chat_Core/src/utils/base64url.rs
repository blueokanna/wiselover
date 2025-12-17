use base64::{
    alphabet,
    engine::{self, general_purpose},
    Engine,
};
const ENGINE: engine::GeneralPurpose =
    engine::GeneralPurpose::new(&alphabet::URL_SAFE, general_purpose::NO_PAD);

pub fn encode<T: AsRef<[u8]>>(bytes: T) -> String {
    ENGINE.encode(bytes)
}

pub fn decode<T: ?Sized + AsRef<[u8]>>(base64_url: &T) -> Result<Vec<u8>, base64::DecodeError> {
    ENGINE.decode(base64_url)
}
