defprotocol Jason.Uo.Encoder do
  @moduledoc """
  Protocol controlling how a value is encoded to JSON.

  ## Deriving

  The protocol allows leveraging the Elixir's `@derive` feature
  to simplify protocol implementation in trivial cases. Accepted
  options are:

    * `:only` - encodes only values of specified keys.
    * `:except` - encodes all struct fields except specified keys.

  By default all keys except the `:__struct__` key are encoded.

  ## Example

  Let's assume a presence of the following struct:

      defmodule Test do
        defstruct [:foo, :bar, :baz]
      end

  If we were to call `@derive Jason.Uo.Encoder` just before `defstruct`,
  an implementation similar to the following implementation would be generated:

      defimpl Jason.Uo.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Uo.Encode.map(Map.take(value, [:foo, :bar, :baz]), opts)
        end
      end

  If we called `@derive {Jason.Uo.Encoder, only: [:foo]}`, an implementation
  similar to the following implementation would be generated:

      defimpl Jason.Uo.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Uo.Encode.map(Map.take(value, [:foo]), opts)
        end
      end

  If we called `@derive {Jason.Uo.Encoder, except: [:foo]}`, an implementation
  similar to the following implementation would be generated:

      defimpl Jason.Uo.Encoder, for: Test do
        def encode(value, opts) do
          Jason.Uo.Encode.map(Map.take(value, [:bar, :baz]), opts)
        end
      end

  The actually generated implementations are more efficient computing some data
  during compilation similar to the macros from the `Jason.Uo.Helpers` module.

  ## Explicit implementation

  If you wish to implement the protocol fully yourself, it is advised to
  use functions from the `Jason.Uo.Encode` module to do the actual iodata
  generation - they are highly optimized and verified to always produce
  valid JSON.
  """

  @type t :: term
  @type opts :: Jason.Uo.Encode.opts()

  @doc """
  Encodes `value` to JSON.

  The argument `opts` is opaque - it can be passed to various functions in
  `Jason.Uo.Encode` (or to the protocol function itself) for encoding values to JSON.
  """
  @spec encode(t, opts) :: iodata
  def encode(value, opts)
end

defimpl Jason.Uo.Encoder, for: Any do
  
  defmacro __deriving__(module, struct, opts) do
    fields = fields_to_encode(struct, opts)
    kv = Enum.map(fields, &{&1, generated_var(&1)})
    escape = quote(do: escape)
    encode_map = quote(do: encode_map)
    user_opts = quote(do: user_opts)
    encode_args = [escape, encode_map, user_opts]
    kv_iodata = Jason.Uo.Codegen.build_kv_iodata(kv, encode_args)

    quote do
      defimpl Jason.Uo.Encoder, for: unquote(module) do
        require Jason.Uo.Helpers

        def encode(%{unquote_splicing(kv)}, {unquote(escape), unquote(encode_map), user_opts}) do
          unquote(kv_iodata)
        end
      end
    end
  end

  # The same as Macro.var/2 except it sets generated: true and handles _ key
  defp generated_var(:_) do
    {:__, [generated: true], __MODULE__.Underscore}
  end
  defp generated_var(name) do
    {name, [generated: true], __MODULE__}
  end

  def encode(%_{} = struct, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      Jason.Uo.Encoder protocol must always be explicitly implemented.

      If you own the struct, you can derive the implementation specifying \
      which fields should be encoded to JSON:

          @derive {Jason.Uo.Encoder, only: [....]}
          defstruct ...

      It is also possible to encode all fields, although this should be \
      used carefully to avoid accidentally leaking private information \
      when new fields are added:

          @derive Jason.Uo.Encoder
          defstruct ...

      Finally, if you don't own the struct you want to encode to JSON, \
      you may use Protocol.derive/3 placed outside of any module:

          Protocol.derive(Jason.Uo.Encoder, NameOfTheStruct, only: [...])
          Protocol.derive(Jason.Uo.Encoder, NameOfTheStruct)
      """
  end

  def encode(value, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value,
      description: "Jason.Uo.Encoder protocol must always be explicitly implemented"
  end

  defp fields_to_encode(struct, opts) do
    fields = Map.keys(struct)

    cond do
      only = Keyword.get(opts, :only) ->
        case only -- fields do
          [] ->
            only

          error_keys ->
            raise ArgumentError,
              "`:only` specified keys (#{inspect(error_keys)}) that are not defined in defstruct: " <>
                "#{inspect(fields -- [:__struct__])}"

        end

      except = Keyword.get(opts, :except) ->
        case except -- fields do
          [] ->
            fields -- [:__struct__ | except]

          error_keys ->
            raise ArgumentError,
              "`:except` specified keys (#{inspect(error_keys)}) that are not defined in defstruct: " <>
                "#{inspect(fields -- [:__struct__])}"

        end

      true ->
        fields -- [:__struct__]
    end
  end
end

# The following implementations are formality - they are already covered
# by the main encoding mechanism in Jason.Uo.Encode, but exist mostly for
# documentation purposes and if anybody had the idea to call the protocol directly.

defimpl Jason.Uo.Encoder, for: Atom do
  def encode(atom, opts) do
    Jason.Uo.Encode.atom(atom, opts)
  end
end

defimpl Jason.Uo.Encoder, for: Integer do
  def encode(integer, _opts) do
    Jason.Uo.Encode.integer(integer)
  end
end

defimpl Jason.Uo.Encoder, for: Float do
  def encode(float, _opts) do
    Jason.Uo.Encode.float(float)
  end
end

defimpl Jason.Uo.Encoder, for: List do
  def encode(list, opts) do
    Jason.Uo.Encode.list(list, opts)
  end
end

defimpl Jason.Uo.Encoder, for: Map do
  def encode(map, opts) do
    Jason.Uo.Encode.map(map, opts)
  end
end

defimpl Jason.Uo.Encoder, for: BitString do
  def encode(binary, opts) when is_binary(binary) do
    Jason.Uo.Encode.string(binary, opts)
  end

  def encode(bitstring, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: bitstring,
      description: "cannot encode a bitstring to JSON"
  end
end

defimpl Jason.Uo.Encoder, for: [Date, Time, NaiveDateTime, DateTime] do
  def encode(value, _opts) do
    [?", @for.to_iso8601(value), ?"]
  end
end

if Code.ensure_loaded?(Decimal) do
  defimpl Jason.Uo.Encoder, for: Decimal do
    def encode(value, _opts) do
      [?", Decimal.to_string(value), ?"]
    end
  end
end

defimpl Jason.Uo.Encoder, for: Jason.Uo.Fragment do
  def encode(%{encode: encode}, opts) do
    encode.(opts)
  end
end
