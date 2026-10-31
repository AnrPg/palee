defmodule Palee.Leads.Domain.PipelineTest do
  use ExUnit.Case, async: true

  alias Palee.Leads.Domain.Pipeline

  @now ~U[2027-05-02 10:00:00.000000Z]

  test "an open lead moves to any other open stage" do
    assert {:ok, %{stage: "trial", stage_changed_at: @now, lost_reason: nil}} =
             Pipeline.move(%{stage: "new"}, "trial", @now)

    assert {:ok, %{stage: "new"}} = Pipeline.move(%{stage: "offer"}, "new", @now)
  end

  test "lost needs a known reason" do
    assert {:error, :invalid_lost_reason} = Pipeline.move(%{stage: "new"}, "lost", @now)

    assert {:ok, %{stage: "lost", lost_reason: "price"}} =
             Pipeline.move(%{stage: "new"}, "lost", @now, lost_reason: "price")
  end

  test "converted is final and reached only by convert" do
    assert {:error, :use_convert} = Pipeline.move(%{stage: "new"}, "converted", @now)
    assert {:error, :lead_converted} = Pipeline.move(%{stage: "converted"}, "new", @now)
    assert {:error, :same_stage} = Pipeline.move(%{stage: "trial"}, "trial", @now)
    assert {:error, :invalid_stage} = Pipeline.move(%{stage: "new"}, "won", @now)
  end

  test "convert links the profile and closes the lead" do
    assert {:ok, %{stage: "converted", user_id: "u1", converted_at: @now}} =
             Pipeline.convert(%{stage: "offer"}, "u1", @now)

    assert {:error, :lead_converted} = Pipeline.convert(%{stage: "converted"}, "u1", @now)
  end

  test "a new enquiry reopens a lost lead and leaves an open one alone" do
    assert %{stage: "new", lost_reason: nil} = Pipeline.reenquiry(%{stage: "lost"}, @now)
    assert Pipeline.reenquiry(%{stage: "trial"}, @now) == %{}
  end
end
