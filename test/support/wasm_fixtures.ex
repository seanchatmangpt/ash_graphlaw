# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.Test.WasmFixtures do
  @moduledoc """
  UNSUPPORTED(generator-capability): test-only assembler for tiny REAL WebAssembly modules.

  These are genuine, spec-valid wasm binaries (validated by a real engine, not described by
  a fake): they let the engine admission gate be exercised on a module with foreign imports,
  a module missing required exports, and a module whose import surface and export set are
  admissible -- none of which needs the multi-megabyte GraphLaw engine.

  Function bodies are deliberately trivial (`gl_alloc` returns 0, `gl_call` returns 0,
  `gl_free` does nothing); the fixtures are only ever compiled and inspected, never used to
  admit a graph.
  """

  @header <<0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00>>
  @wasi "wasi_snapshot_preview1"

  # Function types: 0 = (i32)->(i32) alloc, 1 = (i32,i32)->(i64) call, 2 = (i32,i32)->() free,
  # 3 = (i32)->() import signature.
  @types [
    <<0x60, 1, 0x7F, 1, 0x7F>>,
    <<0x60, 2, 0x7F, 0x7F, 1, 0x7E>>,
    <<0x60, 2, 0x7F, 0x7F, 0>>,
    <<0x60, 1, 0x7F, 0>>
  ]
  @funcs [
    {"gl_alloc", 0, <<0x00, 0x41, 0x00, 0x0B>>},
    {"gl_call", 1, <<0x00, 0x42, 0x00, 0x0B>>},
    {"gl_free", 2, <<0x00, 0x0B>>}
  ]

  @doc "A module whose only import is from the foreign module `env`; exports nothing."
  @spec foreign_imports() :: binary()
  def foreign_imports, do: build([{"env", "host_fn"}], [])

  @doc "A well-formed module that exports only `memory` -- every gl_* export is missing."
  @spec missing_exports() :: binary()
  def missing_exports, do: build([], ["memory"])

  @doc "A module that exports gl_alloc, gl_call and memory but not gl_free."
  @spec missing_gl_free() :: binary()
  def missing_gl_free, do: build([], ["gl_alloc", "gl_call", "memory"])

  @doc """
  A module whose import surface (one `wasi_snapshot_preview1` import) and exports
  (`gl_alloc`, `gl_call`, `gl_free`, `memory`) satisfy the engine gate structurally.
  """
  @spec admissible_surface() :: binary()
  def admissible_surface do
    build([{@wasi, "proc_exit"}], ["gl_alloc", "gl_call", "gl_free", "memory"])
  end

  @doc """
  A module with the full required export set whose only import is `wasi_snapshot_preview1.path_open`,
  a WASI function outside the closed allowlist (the host gives the engine no filesystem).
  """
  @spec forbidden_wasi_import() :: binary()
  def forbidden_wasi_import do
    build([{@wasi, "path_open"}], ["gl_alloc", "gl_call", "gl_free", "memory"])
  end

  @doc """
  A module importing `wasi_snapshot_preview1.fd_write`, an allowlisted name, with the wrong type
  (`(i32) -> ()` instead of `(i32, i32, i32, i32) -> i32`): name-only checking would admit it.
  """
  @spec wrong_type_wasi_import() :: binary()
  def wrong_type_wasi_import do
    build([{@wasi, "fd_write"}], ["gl_alloc", "gl_call", "gl_free", "memory"])
  end

  @doc """
  A complete engine surface with NO imports whose behavior is scripted, for host lifecycle tests:

    * `gl_alloc` returns pointer 8 (inside the one memory page);
    * `gl_call` per `:call` -- `:trap` executes `unreachable`; `{:respond, len}` returns the packed
      result `(8 << 32) | len`, i.e. a response of `len` zero bytes at pointer 8 (never valid JSON);
      `{:json, text}` places `text` in linear memory at pointer 4096 (a data segment; requests are
      written at pointer 8, so keep them under 4 KiB) and returns it as the response, so the host
      reads a real JSON body from a real instance;
      `{:spin, iterations, len}` spins that many loop iterations, then responds like
      `{:respond, len}` (a slow engine, for load shedding);
      `:grow_table` asks the store for 1000 more table elements and reports the outcome as the
      response length (`-1` as 4294967295 when the store's `table_elements` limit denies it, else
      the old size 1), so a host that applies no table limit is distinguishable from one that does;
    * `_initialize` (when `:init_iterations` > 0) spins that many loop iterations, which makes an
      instantiation, and therefore a recycle, measurably slow.

  These are real, spec-valid modules run by the real Wasmtime; they only script the ABI edges a
  healthy GraphLaw would not exercise on demand (a trap, an oversized response, a slow `_initialize`).
  """
  @spec scripted_engine(keyword()) :: binary()
  def scripted_engine(opts \\ []) do
    call = Keyword.get(opts, :call, :trap)
    iterations = Keyword.get(opts, :init_iterations, 0)

    call_body =
      case call do
        :trap ->
          <<0x00, 0x00, 0x0B>>

        {:json, text} ->
          <<0x00, 0x42>> <> s64(Bitwise.bor(Bitwise.bsl(4096, 32), byte_size(text))) <> <<0x0B>>

        {:spin, spins, len} ->
          spin_body(spins) <> <<0x42>> <> s64(Bitwise.bor(Bitwise.bsl(8, 32), len)) <> <<0x0B>>

        {:respond, len} ->
          <<0x00, 0x42>> <> s64(Bitwise.bor(Bitwise.bsl(8, 32), len)) <> <<0x0B>>

        # ref.null func; i32.const 1000; table.grow 0; i64.extend_i32_u; i64.const (8<<32); i64.or
        :grow_table ->
          <<0x00, 0xD0, 0x70, 0x41>> <>
            s64(1000) <> <<0xFC, 0x0F, 0x00, 0xAD, 0x42>> <> s64(Bitwise.bsl(8, 32)) <> <<0x84, 0x0B>>
      end

    init_body = spin_body(iterations) <> <<0x0B>>

    with_init = iterations > 0
    types = @types ++ [<<0x60, 0, 0>>]

    funcs =
      [{0, <<0x00, 0x41, 0x08, 0x0B>>}, {1, call_body}, {2, <<0x00, 0x0B>>}] ++
        if(with_init, do: [{4, init_body}], else: [])

    exports =
      [
        name("gl_alloc") <> <<0x00>> <> u32(0),
        name("gl_call") <> <<0x00>> <> u32(1),
        name("gl_free") <> <<0x00>> <> u32(2)
      ] ++
        if(with_init, do: [name("_initialize") <> <<0x00>> <> u32(3)], else: []) ++
        [name("memory") <> <<0x02>> <> u32(0)]

    IO.iodata_to_binary([
      @header,
      section(1, vec(types)),
      section(3, vec(Enum.map(funcs, fn {t, _} -> u32(t) end))),
      if_present(call == :grow_table, fn -> section(4, vec([<<0x70, 0x00, 1>>])) end),
      section(5, vec([<<0x00, 1>>])),
      section(7, vec(exports)),
      section(10, vec(Enum.map(funcs, fn {_, body} -> u32(byte_size(body)) <> body end))),
      data_section(call)
    ])
  end

  # An active data segment (memory 0, offset 4096) carrying the scripted JSON response, if any.
  defp data_section({:json, text}),
    do: section(11, vec([<<0x00, 0x41>> <> s64(4096) <> <<0x0B>> <> u32(byte_size(text)) <> text]))

  defp data_section(_call), do: []

  @doc "Bytes that are not WebAssembly at all."
  @spec not_wasm() :: binary()
  def not_wasm, do: "this is definitely not a wasm module"

  @doc "Lowercase hex SHA-256 of the given bytes."
  @spec sha256(binary()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc """
  Assembles a module. `imports` is a list of `{module, name}` function imports; `exports`
  is a subset of `~w(gl_alloc gl_call gl_free memory)`.
  """
  @spec build([{String.t(), String.t()}], [String.t()]) :: binary()
  def build(imports, exports) do
    defined = Enum.filter(@funcs, fn {name, _t, _b} -> name in exports end)
    base = length(imports)
    has_memory = "memory" in exports

    func_exports =
      defined
      |> Enum.with_index(base)
      |> Enum.map(fn {{name, _t, _b}, idx} -> name(name) <> <<0x00>> <> u32(idx) end)

    memory_export = if has_memory, do: [name("memory") <> <<0x02>> <> u32(0)], else: []

    sections =
      [section(1, vec(@types))] ++
        if_present(imports != [], fn ->
          section(2, vec(Enum.map(imports, fn {m, n} -> name(m) <> name(n) <> <<0x00>> <> u32(3) end)))
        end) ++
        if_present(defined != [], fn ->
          section(3, vec(Enum.map(defined, fn {_n, t, _b} -> u32(t) end)))
        end) ++
        if_present(has_memory, fn -> section(5, vec([<<0x00, 1>>])) end) ++
        if_present(func_exports ++ memory_export != [], fn ->
          section(7, vec(func_exports ++ memory_export))
        end) ++
        if_present(defined != [], fn ->
          section(10, vec(Enum.map(defined, fn {_n, _t, body} -> u32(byte_size(body)) <> body end)))
        end)

    IO.iodata_to_binary([@header | sections])
  end

  # Function-body prefix: one i32 local counted down from `iterations` in a loop; leaves nothing
  # on the stack.
  defp spin_body(iterations) do
    <<0x01, 0x01, 0x7F, 0x41>> <>
      s64(iterations) <> <<0x21, 0x00, 0x03, 0x40, 0x20, 0x00, 0x41, 0x01, 0x6B, 0x22, 0x00, 0x0D, 0x00, 0x0B>>
  end

  defp if_present(true, fun), do: [fun.()]
  defp if_present(false, _fun), do: []

  defp section(id, payload), do: <<id>> <> u32(byte_size(payload)) <> payload

  defp vec(items), do: u32(length(items)) <> IO.iodata_to_binary(items)

  defp name(string), do: u32(byte_size(string)) <> string

  # signed LEB128 (i32.const / i64.const immediates)
  defp s64(n) do
    byte = Bitwise.band(n, 0x7F)
    rest = Bitwise.bsr(n, 7)

    if (rest == 0 and Bitwise.band(byte, 0x40) == 0) or (rest == -1 and Bitwise.band(byte, 0x40) != 0),
      do: <<byte>>,
      else: <<1::1, byte::7>> <> s64(rest)
  end

  # unsigned LEB128
  defp u32(n) when n < 0x80, do: <<n>>
  defp u32(n), do: <<1::1, Bitwise.band(n, 0x7F)::7>> <> u32(Bitwise.bsr(n, 7))
end
