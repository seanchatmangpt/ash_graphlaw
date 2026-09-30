# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.Generators do
  @moduledoc """
  UNSUPPORTED(generator-capability): StreamData generators shared by `test/property/**`.

  Every generator is bounded (depth, length, magnitude) and pure, so a fixed `--seed`
  reproduces the same cases. Generators build real library values (`Refusal`, `Admitted`,
  `Dsl.Admission`, `Dsl.Runtime`, lease containers); nothing here fakes a collaborator.
  """

  import StreamData
  import ExUnitProperties, only: [gen: 2]

  alias AshGraphLaw.{Admitted, Refusal}
  alias AshGraphLaw.Dsl.{Admission, Runtime}

  @ceilings [:observe, :select, :construct]
  @hostile_codepoints ~c"\\\"\n\r\t<>. #%:\0\e\a\v"

  # -- JSON ------------------------------------------------------------------

  @doc "Valid UTF-8 text of bounded length, including quotes, backslashes and control characters."
  @spec text() :: StreamData.t(String.t())
  def text do
    [
      integer(0x00..0x7F),
      integer(0xA0..0xD7FF),
      integer(0xE000..0x10FFFF),
      member_of(@hostile_codepoints)
    ]
    |> one_of()
    |> list_of(max_length: 24)
    |> map(&List.to_string/1)
  end

  @doc "Printable-ish identifier text (no controls), bounded."
  @spec word() :: StreamData.t(String.t())
  def word, do: string(:alphanumeric, min_length: 1, max_length: 12)

  @doc "A JSON-native scalar."
  @spec json_scalar() :: StreamData.t(term())
  def json_scalar do
    one_of([constant(nil), boolean(), integer(-1_000_000..1_000_000), float(min: -1.0e6, max: 1.0e6), text()])
  end

  @doc "A JSON value with string keys, depth-bounded by `tree/2`."
  @spec json_value() :: StreamData.t(term())
  def json_value do
    tree(json_scalar(), fn child ->
      one_of([list_of(child, max_length: 4), map_of(word(), child, max_length: 4)])
    end)
  end

  @doc "A string-keyed JSON object."
  @spec json_map() :: StreamData.t(map())
  def json_map, do: map_of(word(), json_value(), max_length: 5)

  @doc "Bytes that are NOT valid UTF-8."
  @spec invalid_utf8() :: StreamData.t(binary())
  def invalid_utf8 do
    gen all(prefix <- text(), bad <- member_of([<<0xFF>>, <<0xC0, 0x80>>, <<0xE2, 0x82>>, <<0xF8>>]), suffix <- text()) do
      prefix <> bad <> suffix
    end
  end

  @doc "A term Jason cannot encode."
  @spec unencodable() :: StreamData.t(term())
  def unencodable do
    one_of([
      map(word(), &{:tuple, &1}),
      map(word(), fn w -> {self(), w} end),
      constant(self()),
      constant(make_ref())
    ])
  end

  @doc "Arbitrary binaries, biased toward near-JSON shapes."
  @spec random_binary() :: StreamData.t(binary())
  def random_binary do
    one_of([
      binary(max_length: 64),
      map(json_value(), &Jason.encode!/1),
      map(json_value(), fn value -> String.slice(Jason.encode!(value), 0, 7) end),
      constant(""),
      constant("null"),
      constant("[]"),
      constant("{"),
      member_of(["1", "\"s\"", "true", "{\"ok\":true}", "{\"ok\":false}"])
    ])
  end

  # -- ABI --------------------------------------------------------------------

  @doc "Any 64-bit pattern as an unsigned or signed integer."
  @spec packed() :: StreamData.t(integer())
  def packed do
    one_of([
      integer(0..0xFFFF_FFFF_FFFF_FFFF),
      integer(-0x8000_0000_0000_0000..-1),
      member_of([0, -1, 0xFFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, -0x8000_0000_0000_0000])
    ])
  end

  # -- Refusals ------------------------------------------------------------------

  @doc "Any code of the closed refusal table."
  @spec refusal_code() :: StreamData.t(Refusal.code())
  def refusal_code, do: member_of(Refusal.codes())

  @doc "An atom that is provably outside the closed refusal table."
  @spec foreign_code() :: StreamData.t(atom())
  def foreign_code do
    gen all(word <- word()) do
      candidate = String.to_atom("zz_not_a_code_" <> word)
      if candidate in Refusal.codes(), do: :zz_not_a_code, else: candidate
    end
  end

  @doc "A real `Refusal` for any code with JSON-able details."
  @spec refusal() :: StreamData.t(Refusal.t())
  def refusal do
    gen all(code <- refusal_code(), message <- one_of([constant(nil), text()]), details <- json_map()) do
      Refusal.new(code, message, details)
    end
  end

  @doc "An engine error payload of arbitrary shape (map with string keys, or any term)."
  @spec engine_error() :: StreamData.t(term())
  def engine_error do
    detail_code =
      one_of([
        constant(nil),
        member_of(
          ~w(NotAdmitted PlanRefused ReceiptRequired LeaseRefused ResourceLimit PolicyRefused ReceiptRefused UnverifiedLeaseRefused Refused)
        ),
        word(),
        integer()
      ])

    kind =
      one_of([
        constant(nil),
        member_of(~w(NotSemanticContent Ambiguous EngineRejected Unsupported ResourceLimit)),
        word(),
        integer()
      ])

    payload =
      gen all(
            code <- detail_code,
            kind <- kind,
            message <- one_of([constant(nil), text(), integer()]),
            details <- one_of([json_map(), constant(nil), integer()])
          ) do
        details = if is_map(details) and code != nil, do: Map.put(details, "code", code), else: details

        %{"kind" => kind, "message" => message, "details" => details}
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end

    one_of([payload, json_value(), map(word(), &{:not_a_map, &1})])
  end

  # -- Authority -----------------------------------------------------------------

  @doc "A ceiling atom."
  @spec ceiling() :: StreamData.t(:observe | :select | :construct)
  def ceiling, do: member_of(@ceilings)

  @doc """
  A lease container that is NOT a well-formed signed lease: bare atoms, ceilings under
  `:ceiling`/`:lease`/`:unverified_lease`, unsigned maps, keyword lists and junk. It never
  carries a `:signed_lease` entry.
  """
  @spec unsigned_lease() :: StreamData.t(term())
  def unsigned_lease do
    key = member_of([:ceiling, :lease, :unverified_lease, :now_unix, :scope, :trusted_keys, :unsigned])

    value =
      one_of([
        ceiling(),
        map(ceiling(), &Atom.to_string/1),
        map(ceiling(), &%{"ceiling" => Atom.to_string(&1)}),
        map(ceiling(), &%{ceiling: &1}),
        map(ceiling(), &%{"lease" => %{"ceiling" => Atom.to_string(&1)}}),
        json_value(),
        constant(nil)
      ])

    one_of([
      constant(nil),
      ceiling(),
      map(ceiling(), &Atom.to_string/1),
      integer(),
      text(),
      list_of(value, max_length: 3),
      map_of(key, value, max_length: 4),
      map(map_of(key, value, max_length: 4), &Map.to_list/1),
      map(ceiling(), &[ceiling: &1]),
      constant([]),
      constant(%{})
    ])
  end

  @doc "A ceiling-shaped but structurally broken `:signed_lease` container (must claim `:observe`)."
  @spec malformed_signed_lease() :: StreamData.t(term())
  def malformed_signed_lease do
    broken =
      one_of([
        constant(nil),
        constant(%{}),
        constant("signed"),
        constant(%{"lease" => "construct"}),
        constant(%{"lease" => %{}}),
        constant(%{"lease" => %{"ceiling" => "root"}}),
        constant(%{"lease" => %{"ceiling" => nil}}),
        map(text(), &%{"lease" => %{"ceiling" => &1}})
      ])

    map(broken, fn signed ->
      if signed in [%{"lease" => %{"ceiling" => "observe"}}], do: %{signed_lease: nil}, else: %{signed_lease: signed}
    end)
    |> filter(fn %{signed_lease: signed} -> not well_formed_ceiling?(signed) end)
  end

  defp well_formed_ceiling?(%{"lease" => %{"ceiling" => c}}) when c in ["observe", "select", "construct"], do: true
  defp well_formed_ceiling?(_), do: false

  @doc "A bare `%Admission{}` requiring `ceiling`."
  @spec admission_requiring(atom()) :: struct()
  def admission_requiring(ceiling), do: %Admission{name: :generated, step: :rdfs, ceiling: ceiling}

  # -- Standing / evidence -------------------------------------------------------

  @doc "A 64-character lowercase hex digest."
  @spec sha256_hex() :: StreamData.t(String.t())
  def sha256_hex do
    gen all(bytes <- binary(length: 32)) do
      Base.encode16(bytes, case: :lower)
    end
  end

  @doc "An engine receipt map (string keys)."
  @spec receipt_map() :: StreamData.t(map())
  def receipt_map do
    gen all(
          step <- member_of(~w(shacl n3 hooks plan rdfs owl-rl require-receipt)),
          parent <- sha256_hex(),
          child <- sha256_hex(),
          added <- integer(0..1000),
          extra <- map_of(word(), json_scalar(), max_length: 3)
        ) do
      Map.merge(extra, %{"step" => step, "parent" => parent, "child" => child, "added" => added})
    end
  end

  @doc "An `Admitted` struct built through the real `from_map/1`."
  @spec admitted() :: StreamData.t(Admitted.t())
  def admitted do
    gen all(
          states <- list_of(sha256_hex(), max_length: 4),
          receipts <- list_of(receipt_map(), max_length: 4),
          nquads <- text()
        ) do
      Admitted.from_map(%{"states" => states, "receipts" => receipts, "nquads" => nquads})
    end
  end

  @doc "Anything `Standing.of/1` might be handed: admissions, refusals, engine payloads, junk."
  @spec standing_input() :: StreamData.t(term())
  def standing_input do
    one_of([
      map(admitted(), &{:ok, &1}),
      map(refusal(), &{:error, &1}),
      map(json_value(), &{:ok, &1}),
      map(json_value(), &{:error, &1}),
      json_value(),
      constant(nil),
      constant(:ok),
      constant(:ALIVE),
      constant({:ok, :ALIVE})
    ])
  end

  # -- Admissions / runtime -------------------------------------------------------

  @doc "A `Dsl.Admission` that needs no law module (step `:rdfs`)."
  @spec admission_struct(StreamData.t(atom())) :: StreamData.t(struct())
  def admission_struct(names \\ admission_name()) do
    gen all(name <- names, ceiling <- ceiling()) do
      %Admission{name: name, step: :rdfs, ceiling: ceiling}
    end
  end

  @doc "A small closed pool of admission names, so duplicates occur often."
  @spec admission_name() :: StreamData.t(atom())
  def admission_name, do: member_of([:a, :b, :c, :d, :e])

  @doc "A list of admissions with frequent duplicate names."
  @spec admission_list() :: StreamData.t([struct()])
  def admission_list, do: list_of(admission_struct(), max_length: 8)

  @doc "A runtime section with valid or invalid `timeout_ms`, `max_skew_secs`, `trusted_keys`."
  @spec runtime_struct() :: StreamData.t(struct())
  def runtime_struct do
    junk = one_of([constant(nil), integer(-5..5), float(), text(), constant(:x)])

    gen all(
          timeout <- one_of([integer(1..60_000), junk]),
          skew <- one_of([integer(0..3_600), junk]),
          keys <- one_of([list_of(trusted_key_candidate(), max_length: 4), junk])
        ) do
      %Runtime{timeout_ms: timeout, max_skew_secs: skew, trusted_keys: keys}
    end
  end

  @doc "A valid 64-hex trusted key or a near-miss."
  @spec trusted_key_candidate() :: StreamData.t(term())
  def trusted_key_candidate do
    one_of([
      sha256_hex(),
      map(sha256_hex(), &String.upcase/1),
      map(sha256_hex(), &binary_part(&1, 0, 63)),
      map(sha256_hex(), &(&1 <> "0")),
      map(sha256_hex(), &("g" <> binary_part(&1, 1, 63))),
      constant(""),
      integer(),
      constant(nil)
    ])
  end

  # -- WasmConfig options --------------------------------------------------------

  @limit_keys [
    :fuel,
    :fuel_per_ms,
    :instantiate_fuel,
    :memory_limit_bytes,
    :recycle_bytes,
    :max_queue,
    :max_response_bytes,
    :table_elements,
    :instances,
    :tables,
    :memories,
    :timeout_ms
  ]

  @doc "The limit option keys `WasmConfig.limits/1` understands."
  @spec limit_keys() :: [atom()]
  def limit_keys, do: @limit_keys

  @doc "A keyword list of limit options with valid and invalid values, as a map for shrinking."
  @spec limit_opts() :: StreamData.t(keyword())
  def limit_opts do
    value = one_of([integer(1..1_000_000), integer(-3..0), float(), text(), constant(nil), constant(:x)])

    map(map_of(member_of(@limit_keys), value, max_length: 6), &Map.to_list/1)
  end

  # -- Projection subjects ---------------------------------------------------------

  @doc "Non-projectable subjects."
  @spec foreign_subject() :: StreamData.t(term())
  def foreign_subject do
    one_of([
      constant(nil),
      integer(),
      text(),
      constant(%{}),
      constant(URI.parse("urn:x")),
      list_of(integer(), max_length: 3)
    ])
  end
end
