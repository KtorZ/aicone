use aiken/collection/list
use aiken/collection/pairs
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Credential}
use cardano/assets.{Lovelace}
use cardano/transaction.{ValidityRange}

pub type MultisigScript {
  Signature { key_hash: ByteArray }
  AllOf { scripts: List<MultisigScript> }
  AnyOf { scripts: List<MultisigScript> }
  AtLeast { required: Int, scripts: List<MultisigScript> }
  Before { time: Int }
  After { time: Int }
  Script { script_hash: ByteArray }
}

pub fn satisfied(
  script: MultisigScript,
  signatories: List<ByteArray>,
  valid_range: ValidityRange,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  when script is {
    Signature { key_hash } -> list.has(signatories, key_hash)
    AllOf { scripts } ->
      list.all(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    AnyOf { scripts } ->
      list.any(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    AtLeast { required, scripts } ->
      required <= list.count(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    // TODO: could be simplified with https://github.com/aiken-lang/aiken/issues/566
    Before { time } ->
      when valid_range.upper_bound.bound_type is {
        Finite(hi) ->
          if valid_range.upper_bound.is_inclusive {
            hi <= time
          } else {
            hi < time
          }
        _ -> False
      }
    After { time } ->
      when valid_range.lower_bound.bound_type is {
        Finite(lo) ->
          if valid_range.lower_bound.is_inclusive {
            time <= lo
          } else {
            time < lo
          }
        _ -> False
      }
    Script { script_hash } ->
      pairs.has_key(withdrawals, address.Script(script_hash))
  }
}

test satisfying() {
  let key_hash1 = "key1"
  let key_hash2 = "key2"
  let key_hash3 = "key3"
  let sig1 = Signature { key_hash: key_hash1 }
  trace @"Signature": sig1
  let sig2 = Signature { key_hash: key_hash2 }
  let sig3 = Signature { key_hash: key_hash3 }
  let all_of = AllOf { scripts: [sig1, sig2] }
  trace @"AllOf": all_of
  let any_of = AnyOf { scripts: [sig1, sig2] }
  trace @"AnyOf": any_of
  let at_least = AtLeast { required: 2, scripts: [sig1, sig2, sig3] }
  trace @"AtLeast": at_least
  let before = Before { time: 10 }
  trace @"Before": before
  let after = After { time: 10 }
  trace @"After": after
  let between = AllOf { scripts: [After { time: 10 }, Before { time: 15 }] }
  trace @"Between": between
  let script = Script { script_hash: "some_script" }
  trace @"Script": script
  let vesting =
    AnyOf {
      scripts: [
        AllOf { scripts: [before, sig1] },
        // clawback
        AllOf { scripts: [after, sig2] },
        // dao clawback
        script,
      ],
    }
  trace @"Vesting": vesting
  // vested
  let valid_range =
    fn(lo: Int, hi: Int) -> ValidityRange {
      Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(lo),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(hi),
          is_inclusive: False,
        },
      }
    }
  let no_w: Pairs<Credential, Lovelace> =
    []
  let correct_w =
    [Pair(address.Script("some_script"), 0)]
  let incorrect_w =
    [Pair(address.Script("other_script"), 0)]
  let both_w =
    [
      Pair(address.Script("some_script"), 0),
      Pair(address.Script("other_script"), 0),
    ]
  // Helper method because ? binds more tightly than !
  let unsatisfied =
    fn(
      n: MultisigScript,
      s: List<ByteArray>,
      v: ValidityRange,
      w: Pairs<Credential, Lovelace>,
    ) {
      !satisfied(n, s, v, w)
    }
  list.all(
    [
      satisfied(sig1, [key_hash1], valid_range(0, 1), no_w)?,
      satisfied(sig2, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      satisfied(all_of, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      satisfied(any_of, [key_hash2], valid_range(0, 1), no_w)?,
      satisfied(at_least, [key_hash2, key_hash3], valid_range(0, 1), no_w)?,
      satisfied(before, [], valid_range(0, 5), no_w)?,
      satisfied(after, [], valid_range(15, 20), no_w)?,
      satisfied(after, [], valid_range(10, 15), no_w)?,
      satisfied(between, [], valid_range(12, 13), no_w)?,
      satisfied(script, [], valid_range(0, 1), correct_w)?,
      satisfied(script, [], valid_range(0, 1), both_w)?,
      satisfied(vesting, [key_hash1], valid_range(0, 5), no_w)?,
      satisfied(vesting, [key_hash2], valid_range(15, 20), no_w)?,
      satisfied(vesting, [key_hash3], valid_range(0, 1), correct_w)?,
      unsatisfied(sig1, [key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(sig3, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(all_of, [key_hash1, key_hash3], valid_range(0, 1), no_w)?,
      unsatisfied(any_of, [key_hash3], valid_range(0, 1), no_w)?,
      unsatisfied(at_least, [key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(before, [], valid_range(5, 15), no_w)?,
      unsatisfied(before, [], valid_range(5, 10), no_w)?,
      unsatisfied(before, [], valid_range(10, 10), no_w)?,
      unsatisfied(after, [], valid_range(5, 15), no_w)?,
      unsatisfied(between, [], valid_range(0, 5), no_w)?,
      unsatisfied(between, [], valid_range(0, 13), no_w)?,
      unsatisfied(between, [], valid_range(0, 20), no_w)?,
      unsatisfied(between, [], valid_range(13, 20), no_w)?,
      unsatisfied(between, [], valid_range(13, 15), no_w)?,
      unsatisfied(between, [], valid_range(15, 20), no_w)?,
      unsatisfied(script, [], valid_range(0, 1), incorrect_w)?,
      unsatisfied(vesting, [key_hash2], valid_range(0, 5), no_w)?,
      unsatisfied(vesting, [key_hash1], valid_range(15, 20), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(10, 10), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(0, 5), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(15, 20), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(15, 20), incorrect_w)?,
    ],
    fn(n) { n },
  )
}
