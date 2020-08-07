defmodule Absinthe.SchemaTest do
  # can't async due to capture io
  use Absinthe.Case

  alias Absinthe.Schema
  alias Absinthe.Type

  describe "built-in types" do
    def load_valid_schema do
      load_schema("valid_schema")
    end

    test "are loaded" do
      load_valid_schema()

      builtin_types =
        Absinthe.Fixtures.ValidSchema
        |> Absinthe.Schema.types()
        |> Enum.filter(&Absinthe.Type.built_in?(&1))

      assert length(builtin_types) > 0

      Enum.each(builtin_types, fn type ->
        assert Absinthe.Fixtures.ValidSchema.__absinthe_type__(type.identifier) ==
                 Absinthe.Fixtures.ValidSchema.__absinthe_type__(type.name)
      end)

      int = Absinthe.Fixtures.ValidSchema.__absinthe_type__(:integer)
      assert 1 == Type.Scalar.serialize(int, 1)
      assert {:ok, 1} == Type.Scalar.parse(int, 1, %{})
    end
  end

  describe "using the same identifier" do
    test "raises an exception" do
      assert_schema_error("schema_with_duplicate_identifiers", [
        %{
          phase: Absinthe.Phase.Schema.Validation.TypeNamesAreUnique,
          extra: %{artifact: "Absinthe type identifier", value: :person}
        }
      ])
    end
  end

  describe "using the same name" do
    def load_duplicate_name_schema do
      load_schema("schema_with_duplicate_names")
    end

    test "raises an exception" do
      assert_schema_error("schema_with_duplicate_names", [
        %{
          phase: Absinthe.Phase.Schema.Validation.TypeNamesAreUnique,
          extra: %{artifact: "Type name", value: "Person"}
        }
      ])
    end
  end

  defmodule SourceSchema do
    use Absinthe.Schema

    @desc "can describe query"
    query do
      field :foo,
        type: :foo,
        resolve: fn _, _ -> {:ok, %{name: "Fancy Foo!"}} end
    end

    object :foo do
      field :name, :string
    end
  end

  defmodule UserSchema do
    use Absinthe.Schema

    import_types SourceSchema

    query do
      field :foo,
        type: :foo,
        resolve: fn _, _ -> {:ok, %{name: "A different fancy Foo!"}} end

      field :bar,
        type: :bar,
        resolve: fn _, _ -> {:ok, %{name: "A plain old bar"}} end
    end

    object :bar do
      field :name, :string
    end
  end

  defmodule ThirdSchema do
    use Absinthe.Schema

    interface :named do
      field :name, :string
      resolve_type fn _, _ -> nil end
    end

    interface :aged do
      field :age, :integer
      resolve_type fn _, _ -> nil end
    end

    union :pet do
      types [:dog]
    end

    object :dog do
      field :name, :string
    end

    enum :some_enum do
      values([:a, :b])
    end

    interface :loop do
      field :loop, :loop
    end

    directive :directive do
      arg :baz, :dir_enum
    end

    enum :dir_enum do
      value :foo
    end

    query do
      field :loop, :loop
      field :enum_field, :some_enum
      field :object_field, :user
      field :interface_field, :aged
      field :union_field, :pet
    end

    object :person do
      field :age, :integer
      interface :aged
    end

    import_types UserSchema

    object :user do
      field :name, :string
      interface :named
    end

    object :baz do
      field :name, :string
    end
  end

  test "can have a description on the root query" do
    assert "can describe query" == Absinthe.Schema.lookup_type(SourceSchema, :query).description
  end

  describe "using import_types" do
    test "adds the types from a parent" do
      assert %{foo: "Foo", bar: "Bar"} = UserSchema.__absinthe_types__()
      assert "Foo" == UserSchema.__absinthe_type__(:foo).name
    end

    test "adds the types from a grandparent" do
      assert %{foo: "Foo", bar: "Bar", baz: "Baz"} = ThirdSchema.__absinthe_types__(:all)
      assert "Foo" == ThirdSchema.__absinthe_type__(:foo).name
    end
  end

  describe "lookup_type" do
    test "is supported" do
      assert "Foo" == Schema.lookup_type(ThirdSchema, :foo).name
    end
  end

  defmodule RootsSchema do
    use Absinthe.Schema

    import_types SourceSchema

    query do
      field :name,
        type: :string,
        args: [
          family_name: [type: :boolean]
        ]
    end

    mutation name: "MyRootMutation" do
      field :name, :string
    end

    subscription name: "RootSubscriptionTypeThing" do
      field :name, :string
    end
  end

  describe "referenced_types" do
    test "does not contain introspection types" do
      assert !Enum.any?(
               Schema.referenced_types(ThirdSchema),
               &Type.introspection?/1
             )
    end

    test "contains enums" do
      types =
        ThirdSchema
        |> Absinthe.Schema.referenced_types()
        |> Enum.map(& &1.identifier)

      assert :some_enum in types
      assert :dir_enum in types
    end

    test "contains interfaces" do
      types =
        ThirdSchema
        |> Absinthe.Schema.referenced_types()
        |> Enum.map(& &1.identifier)

      assert :named in types
    end

    test "contains types only connected via interfaces" do
      types =
        ThirdSchema
        |> Absinthe.Schema.referenced_types()
        |> Enum.map(& &1.identifier)

      assert :person in types
    end

    test "contains types only connected via union" do
      types =
        ThirdSchema
        |> Absinthe.Schema.referenced_types()
        |> Enum.map(& &1.identifier)

      assert :dog in types
    end
  end

  describe "introspection_types" do
    test "is not empty" do
      assert !Enum.empty?(Schema.introspection_types(ThirdSchema))
    end

    test "are introspection types" do
      assert Enum.all?(
               Schema.introspection_types(ThirdSchema),
               &Type.introspection?/1
             )
    end
  end

  describe "root fields" do
    test "can have a default name" do
      assert "RootQueryType" == Schema.lookup_type(RootsSchema, :query).name
    end

    test "can have a custom name" do
      assert "MyRootMutation" == Schema.lookup_type(RootsSchema, :mutation).name
    end

    test "supports subscriptions" do
      assert "RootSubscriptionTypeThing" == Schema.lookup_type(RootsSchema, :subscription).name
    end
  end

  describe "fields" do
    test "have the correct structure in query" do
      assert %Type.Field{name: "name"} = Schema.lookup_type(RootsSchema, :query).fields.name
    end

    test "have the correct structure in subscription" do
      assert %Type.Field{name: "name"} =
               Schema.lookup_type(RootsSchema, :subscription).fields.name
    end
  end

  describe "arguments" do
    test "have the correct structure" do
      assert %Type.Argument{name: "family_name"} =
               Schema.lookup_type(RootsSchema, :query).fields.name.args.family_name
    end
  end

  describe "to_sdl/1" do
    test "return schema sdl" do
      assert Schema.to_sdl(SourceSchema) == """
             schema {\n  query: RootQueryType\n}\n\ntype Foo {\n  name: String\n}\n\n\"can describe query\"\ntype RootQueryType {\n  foo: Foo\n}
             """
    end
  end

  defmodule FragmentSpreadSchema do
    use Absinthe.Schema

    @viewer %{id: "ABCD", name: "Bruce"}

    query do
      field :viewer, :viewer do
        resolve fn _, _ -> {:ok, @viewer} end
      end
    end

    object :viewer do
      field :id, :id
      field :name, :string
    end
  end

  describe "multiple fragment spreads" do
    @query """
    query Viewer{viewer{id,...F1}}
    fragment F0 on Viewer{name,id}
    fragment F1 on Viewer{id,...F0}
    """
    test "builds the correct result" do
      assert_result(
        {:ok, %{data: %{"viewer" => %{"id" => "ABCD", "name" => "Bruce"}}}},
        run(@query, FragmentSpreadSchema)
      )
    end
  end

  defmodule MetadataSchema do
    use Absinthe.Schema

    query do
      # Query type must exist
    end

    object :foo, meta: [foo: "bar"] do
      meta :sql_table, "foos"
      meta cache: false, eager: true

      field :bar, :string do
        meta :nice, "yup"
      end

      meta duplicate: "not this value"
      meta duplicate: "this value"

      meta nested: [a: 1]
      meta nested: [b: 1]
    end

    input_object :input_foo do
      meta :is_input, true

      field :bar, :string do
        meta :nice, "nope"
      end
    end

    enum :color do
      meta :rgb_only, true
      value :red
      value :blue
      value :green
    end

    scalar :my_scalar do
      meta :is_scalar, true
      # Missing parse and serialize
    end

    interface :named do
      meta :is_interface, true

      field :name, :string do
        meta :is_name, true
      end
    end

    union :result do
      types [:foo]
      meta :is_union, true
    end
  end

  describe "can add metadata to an object" do
    test "sets object metadata" do
      foo = Schema.lookup_type(MetadataSchema, :foo)

      assert Enum.sort(
               eager: true,
               cache: false,
               sql_table: "foos",
               foo: "bar",
               duplicate: "this value",
               nested: [a: 1, b: 1]
             ) ==
               Enum.sort(foo.__private__[:meta])

      assert Type.meta(foo, :sql_table) == "foos"
      assert Type.meta(foo, :cache) == false
      assert Type.meta(foo, :eager) == true
    end

    test "sets value to last specified for a key" do
      foo = Schema.lookup_type(MetadataSchema, :foo)
      assert Type.meta(foo, :duplicate) == "this value"
    end

    test "sets value to merged keyword list when multiple keyword list values are specified for same key" do
      foo = Schema.lookup_type(MetadataSchema, :foo)
      assert Type.meta(foo, :nested) == [a: 1, b: 1]
    end

    test "sets field metadata" do
      foo = Schema.lookup_type(MetadataSchema, :foo)
      assert %{__private__: [meta: [nice: "yup"]]} = foo.fields[:bar]
      assert Type.meta(foo.fields[:bar], :nice) == "yup"
    end

    test "sets input object metadata" do
      input_foo = Schema.lookup_type(MetadataSchema, :input_foo)
      assert %{__private__: [meta: [is_input: true]]} = input_foo
      assert Type.meta(input_foo, :is_input) == true
    end

    test "sets input object field metadata" do
      input_foo = Schema.lookup_type(MetadataSchema, :input_foo)
      assert %{__private__: [meta: [nice: "nope"]]} = input_foo.fields[:bar]
      assert Type.meta(input_foo.fields[:bar], :nice) == "nope"
    end

    test "sets enum metadata" do
      color = Schema.lookup_type(MetadataSchema, :color)
      assert %{__private__: [meta: [rgb_only: true]]} = color
      assert Type.meta(color, :rgb_only) == true
    end

    test "sets scalar metadata" do
      my_scalar = Schema.lookup_type(MetadataSchema, :my_scalar)
      assert %{__private__: [meta: [is_scalar: true]]} = my_scalar
      assert Type.meta(my_scalar, :is_scalar) == true
    end

    test "sets interface metadata" do
      named = Schema.lookup_type(MetadataSchema, :named)
      assert %{__private__: [meta: [is_interface: true]]} = named
      assert Type.meta(named, :is_interface) == true
    end

    test "sets interface field metadata" do
      named = Schema.lookup_type(MetadataSchema, :named)
      assert %{__private__: [meta: [is_name: true]]} = named.fields[:name]
      assert Type.meta(named.fields[:name], :is_name) == true
    end

    test "sets union metadata" do
      result = Schema.lookup_type(MetadataSchema, :result)
      assert %{__private__: [meta: [is_union: true]]} = result
      assert Type.meta(result, :is_union) == true
    end
  end

  defmodule TelemetrySchema do
    use Absinthe.Schema

    query do
      field(:example, :example)
    end

    object :example do
      field(:default_disabled, :string)

      field(:default_enabled, :string) do
        resolve(fn _, _, _ -> {:ok, "Hello world"} end)
      end

      field(:explicitly_disabled, :string) do
        resolve(fn _, _, _ -> {:ok, "Hello world"} end)
        meta(absinthe_telemetry: false)
      end

      field(:explicitly_enabled, :string) do
        meta(absinthe_telemetry: true)
      end
    end
  end

  describe "telemetry for a field" do
    test "defaults to disabled when no resolver is defined" do
      assert [_] = lookup_compiled_field_middleware(TelemetrySchema, "Example", :default_disabled)
    end

    test "defaults to enabled when a resolver is defined" do
      assert [{Absinthe.Middleware.Telemetry, _}, _] =
               lookup_compiled_field_middleware(TelemetrySchema, "Example", :default_enabled)
    end

    test "can be explicitly disabled by setting meta(absinthe_telemetry: false)" do
      assert [_] =
               lookup_compiled_field_middleware(TelemetrySchema, "Example", :explicitly_disabled)
    end

    test "can be explicitly enabled by setting meta(absinthe_telemetry: true)" do
      assert [{Absinthe.Middleware.Telemetry, _}, _] =
               lookup_compiled_field_middleware(TelemetrySchema, "Example", :explicitly_enabled)
    end
  end

  defp lookup_compiled_field_middleware(mod, type_ident, field_ident) do
    import ExperimentalNotationHelpers

    %{middleware: middleware} = lookup_compiled_field(mod, type_ident, field_ident)

    case middleware do
      [{{Absinthe.Middleware, :shim}, _}] ->
        Absinthe.Middleware.unshim(middleware, mod)

      middleware ->
        middleware
    end
  end
end
