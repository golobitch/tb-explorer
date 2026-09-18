//! Turning replies into structs and filters into bytes.
//!
//! The structs in `models` are `#[repr(C)]` copies of what `tb_client.h` declares, so decoding is
//! an unaligned read per record rather than field-by-field surgery. The tests below pin every size
//! and offset against the header, which is what makes that shortcut safe to rely on.

use crate::client::TbError;
use crate::models::*;

/// Reads a reply as a slice of records.
pub fn decode<T: Copy>(bytes: &[u8], size: usize) -> Result<Vec<T>, TbError> {
    debug_assert_eq!(size, size_of::<T>());
    if bytes.len() % size != 0 {
        return Err(TbError::Decode(format!(
            "{} bytes is not a whole number of {size}-byte records",
            bytes.len()
        )));
    }
    Ok(bytes
        .chunks_exact(size)
        .map(|chunk| {
            // SAFETY: the chunk is exactly one record long, and `T` is a repr(C) struct of plain
            // integers, so every bit pattern is valid. The read is unaligned because the reply
            // buffer carries no alignment guarantee.
            unsafe { chunk.as_ptr().cast::<T>().read_unaligned() }
        })
        .collect())
}

pub fn accounts(bytes: &[u8]) -> Result<Vec<Account>, TbError> {
    decode(bytes, ACCOUNT_SIZE)
}

pub fn transfers(bytes: &[u8]) -> Result<Vec<Transfer>, TbError> {
    decode(bytes, TRANSFER_SIZE)
}

pub fn balances(bytes: &[u8]) -> Result<Vec<Balance>, TbError> {
    decode(bytes, BALANCE_SIZE)
}

/// Ids as 16 little-endian bytes each, which is what the lookup operations take.
pub fn ids(ids: &[u128]) -> Vec<u8> {
    let mut out = Vec::with_capacity(ids.len() * ID_SIZE);
    for id in ids {
        out.extend_from_slice(&id.to_le_bytes());
    }
    out
}

const ACCOUNT_FILTER_DEBITS: u32 = 1 << 0;
const ACCOUNT_FILTER_CREDITS: u32 = 1 << 1;
const ACCOUNT_FILTER_REVERSED: u32 = 1 << 2;
const QUERY_FILTER_REVERSED: u32 = 1 << 0;

pub fn account_filter(filter: &AccountFilter) -> Vec<u8> {
    let mut out = vec![0u8; ACCOUNT_FILTER_SIZE];
    out[0..16].copy_from_slice(&filter.account_id.to_le_bytes());
    out[16..32].copy_from_slice(&filter.user_data_128.to_le_bytes());
    out[32..40].copy_from_slice(&filter.user_data_64.to_le_bytes());
    out[40..44].copy_from_slice(&filter.user_data_32.to_le_bytes());
    out[44..46].copy_from_slice(&filter.code.to_le_bytes());
    out[104..112].copy_from_slice(&filter.timestamp_min.to_le_bytes());
    out[112..120].copy_from_slice(&filter.timestamp_max.to_le_bytes());
    out[120..124].copy_from_slice(&clamp_limit(filter.limit).to_le_bytes());

    // Neither side selected would mean "no transfers at all", which is never what a caller wants.
    let (debits, credits) = if filter.debits || filter.credits {
        (filter.debits, filter.credits)
    } else {
        (true, true)
    };
    let mut flags = 0u32;
    if debits {
        flags |= ACCOUNT_FILTER_DEBITS;
    }
    if credits {
        flags |= ACCOUNT_FILTER_CREDITS;
    }
    if filter.reversed {
        flags |= ACCOUNT_FILTER_REVERSED;
    }
    out[124..128].copy_from_slice(&flags.to_le_bytes());
    out
}

pub fn query_filter(filter: &QueryFilter) -> Vec<u8> {
    let mut out = vec![0u8; QUERY_FILTER_SIZE];
    out[0..16].copy_from_slice(&filter.user_data_128.to_le_bytes());
    out[16..24].copy_from_slice(&filter.user_data_64.to_le_bytes());
    out[24..28].copy_from_slice(&filter.user_data_32.to_le_bytes());
    out[28..32].copy_from_slice(&filter.ledger.to_le_bytes());
    out[32..34].copy_from_slice(&filter.code.to_le_bytes());
    out[40..48].copy_from_slice(&filter.timestamp_min.to_le_bytes());
    out[48..56].copy_from_slice(&filter.timestamp_max.to_le_bytes());
    out[56..60].copy_from_slice(&clamp_limit(filter.limit).to_le_bytes());
    let flags = if filter.reversed {
        QUERY_FILTER_REVERSED
    } else {
        0
    };
    out[60..64].copy_from_slice(&flags.to_le_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The offsets `tb_client.h` defines, and the ones the Swift client pins in WireTests. Two
    /// implementations agreeing on these is what makes the repr(C) shortcut safe.
    #[test]
    fn structs_match_the_header() {
        assert_eq!(size_of::<Account>(), ACCOUNT_SIZE);
        assert_eq!(size_of::<Transfer>(), TRANSFER_SIZE);
        assert_eq!(size_of::<Balance>(), BALANCE_SIZE);

        assert_eq!(std::mem::offset_of!(Account, id), 0);
        assert_eq!(std::mem::offset_of!(Account, debits_pending), 16);
        assert_eq!(std::mem::offset_of!(Account, debits_posted), 32);
        assert_eq!(std::mem::offset_of!(Account, credits_pending), 48);
        assert_eq!(std::mem::offset_of!(Account, credits_posted), 64);
        assert_eq!(std::mem::offset_of!(Account, user_data_128), 80);
        assert_eq!(std::mem::offset_of!(Account, user_data_64), 96);
        assert_eq!(std::mem::offset_of!(Account, user_data_32), 104);
        assert_eq!(std::mem::offset_of!(Account, ledger), 112);
        assert_eq!(std::mem::offset_of!(Account, code), 116);
        assert_eq!(std::mem::offset_of!(Account, flags), 118);
        assert_eq!(std::mem::offset_of!(Account, timestamp), 120);

        assert_eq!(std::mem::offset_of!(Transfer, debit_account_id), 16);
        assert_eq!(std::mem::offset_of!(Transfer, credit_account_id), 32);
        assert_eq!(std::mem::offset_of!(Transfer, amount), 48);
        assert_eq!(std::mem::offset_of!(Transfer, pending_id), 64);
        assert_eq!(std::mem::offset_of!(Transfer, user_data_128), 80);
        assert_eq!(std::mem::offset_of!(Transfer, timeout), 108);
        assert_eq!(std::mem::offset_of!(Transfer, ledger), 112);
        assert_eq!(std::mem::offset_of!(Transfer, code), 116);
        assert_eq!(std::mem::offset_of!(Transfer, timestamp), 120);

        assert_eq!(std::mem::offset_of!(Balance, debits_posted), 16);
        assert_eq!(std::mem::offset_of!(Balance, credits_posted), 48);
        assert_eq!(std::mem::offset_of!(Balance, timestamp), 64);
    }

    #[test]
    fn a_transfer_round_trips_through_bytes() {
        let transfer = Transfer {
            id: u128::MAX,
            debit_account_id: 1016,
            credit_account_id: 1017,
            amount: 71_001,
            pending_id: 0,
            user_data_128: 9020,
            user_data_64: 6,
            user_data_32: 3,
            timeout: 0,
            ledger: 840,
            code: 20,
            flags: transfer_flags::PENDING,
            timestamp: 1_789_561_992_527_027_008,
        };
        // SAFETY: Transfer is repr(C) and made only of integers.
        let bytes = unsafe {
            std::slice::from_raw_parts((&raw const transfer).cast::<u8>(), TRANSFER_SIZE)
        };
        let decoded = transfers(bytes).unwrap();
        assert_eq!(decoded, vec![transfer]);

        let two = [bytes, bytes].concat();
        assert_eq!(transfers(&two).unwrap().len(), 2);
    }

    #[test]
    fn a_misaligned_reply_is_an_error_not_a_panic() {
        assert!(matches!(transfers(&[0u8; 130]), Err(TbError::Decode(_))));
    }

    #[test]
    fn lookup_ids_are_sixteen_little_endian_bytes_each() {
        let bytes = ids(&[1, u128::MAX]);
        assert_eq!(bytes.len(), 32);
        assert_eq!(bytes[0], 1);
        assert_eq!(&bytes[16..], &[0xFF; 16]);
    }

    #[test]
    fn a_query_filter_encodes_where_the_header_says() {
        let filter = QueryFilter {
            ledger: 840,
            code: 20,
            limit: 0,
            reversed: true,
            ..Default::default()
        };
        let bytes = query_filter(&filter);
        assert_eq!(bytes.len(), QUERY_FILTER_SIZE);
        assert_eq!(u32::from_le_bytes(bytes[28..32].try_into().unwrap()), 840);
        assert_eq!(u16::from_le_bytes(bytes[32..34].try_into().unwrap()), 20);
        assert_eq!(
            u32::from_le_bytes(bytes[56..60].try_into().unwrap()),
            DEFAULT_LIMIT,
            "an unset limit becomes the default"
        );
        assert_eq!(
            u32::from_le_bytes(bytes[60..64].try_into().unwrap()),
            QUERY_FILTER_REVERSED
        );
    }

    #[test]
    fn an_account_filter_defaults_to_both_sides_and_clamps_the_limit() {
        let neither = AccountFilter {
            account_id: 1015,
            debits: false,
            credits: false,
            limit: MAX_LIMIT * 2,
            ..Default::default()
        };
        let bytes = account_filter(&neither);
        assert_eq!(
            u32::from_le_bytes(bytes[120..124].try_into().unwrap()),
            MAX_LIMIT
        );
        assert_eq!(
            u32::from_le_bytes(bytes[124..128].try_into().unwrap()),
            ACCOUNT_FILTER_DEBITS | ACCOUNT_FILTER_CREDITS,
            "neither side selected means both, never none"
        );
    }

    #[test]
    fn the_cursor_steps_past_the_row_already_seen() {
        assert_eq!(next_cursor(10, false), (11, 0));
        assert_eq!(next_cursor(10, true), (0, 9));
    }

    #[test]
    fn flags_decode_in_bit_order() {
        let names = flag_names(
            transfer_flags::PENDING | transfer_flags::LINKED,
            &transfer_flags::NAMES,
        );
        assert_eq!(names, vec!["linked", "pending"]);
        assert_eq!(
            flag_names(1 << 12, &transfer_flags::NAMES),
            vec!["unknown_bit_12"]
        );
    }
}
