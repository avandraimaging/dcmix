defmodule Dcmix.UIDTest do
  use ExUnit.Case, async: true

  alias Dcmix.UID

  doctest Dcmix.UID

  describe "implementation_version_name/0" do
    test "fits an SH value" do
      assert String.length(UID.implementation_version_name()) <= 16
    end
  end

  describe "generate/0" do
    test "is a valid UID: digits and dots, at most 64 characters, no leading zeros" do
      for _ <- 1..1_000 do
        uid = UID.generate()

        assert String.length(uid) <= 64
        assert uid =~ ~r/\A(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*\z/
      end
    end

    test "is under the root's .1.1 arc, followed by the date, time and a random number" do
      today = fn -> Calendar.strftime(DateTime.utc_now(), "%Y%m%d") end
      before = today.()

      assert [date, time, random] =
               UID.generate()
               |> String.replace_prefix("1.2.826.0.1.3680043.10.1712.1.1.", "")
               |> String.split(".")

      assert date in [before, today.()]
      assert String.to_integer(time) in 0..235_959
      assert String.to_integer(random) > 0
    end

    test "gives a different UID each call" do
      uids = for _ <- 1..1_000, do: UID.generate()
      assert length(Enum.uniq(uids)) == 1_000
    end
  end
end
