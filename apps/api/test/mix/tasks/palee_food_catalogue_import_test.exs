defmodule Mix.Tasks.Palee.FoodCatalogue.ImportTest do
  @moduledoc "ADR-421: a licensed product list is imported for the Greek source of the chain."

  use Palee.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Palee.FoodCatalogue.Import
  alias Palee.Infrastructure.Nutrition.EctoFoodCatalogue

  test "valid barcodes are imported with the list's licence; bad rows are skipped" do
    path = Path.join(System.tmp_dir!(), "catalogue-#{System.unique_integer([:positive])}.csv")
    on_exit(fn -> File.rm(path) end)

    File.write!(path, """
    Barcode;Name;Brand;Quantity
    5201234500006;Φέτα ΠΟΠ;Μάρκα;400 g
    5201234500007;Λάθος ψηφίο;;
    2001234000000;Κωδικός καταστήματος;;
    """)

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    capture_io(fn ->
      Import.run([
        path,
        "--list",
        "gr_test",
        "--source",
        "Λίστα δοκιμής",
        "--licence",
        "CC BY 4.0"
      ])
    end)

    assert_received {:mix_shell, :info, ["Imported 1 products into gr_test; skipped 2 rows"]}

    assert {:ok, %{name: "Φέτα ΠΟΠ", quantity: "400 g", attribution: %{"licence" => "CC BY 4.0"}}} =
             EctoFoodCatalogue.lookup("5201234500006", "el")

    assert_raise Mix.Error, fn -> Import.run([path]) end
  end
end
