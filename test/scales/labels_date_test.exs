defmodule Scales.LabelsDateTest do
  use ExUnit.Case, async: true

  alias Scales.Labels

  # Golden: every expected label below is R's own, from R 4.6.1 with scales 1.4.0 and hms (the
  # image `giggly-r:ggplot2-4.0.3-hms`), each from the call in the comment above it, where `D()`
  # is `as.Date(c(...))`, `U()` `as.POSIXct(c(...), tz = "UTC")` and `NY()` the same in
  # America/New_York; but for the departures, each said so. They move only if scales' or R's
  # formatting does.

  @zones [time_zone_database: Tz.TimeZoneDatabase]
  @new_york [tz: "America/New_York"] ++ @zones

  # Times `step` seconds apart from `start`, in `zone`.
  defp series(start, step, count, zone \\ "Etc/UTC") do
    for index <- 0..(count - 1) do
      start
      |> DateTime.add(index * step, :second)
      |> DateTime.shift_zone!(zone, Tz.TimeZoneDatabase)
    end
  end

  defp naive_series(start, step, count) do
    for index <- 0..(count - 1), do: NaiveDateTime.add(start, index * step, :second)
  end

  defp in_zone(naive, zone), do: DateTime.from_naive!(naive, zone, Tz.TimeZoneDatabase)

  # 2019-12-31 22:00 in New York, hourly.
  defp new_year_hours, do: series(~U[2020-01-01 03:00:00Z], 3600, 4, "America/New_York")

  # 2021-11-07 00:00 in New York, every half hour across the hour repeated.
  defp fall_back, do: series(~U[2021-11-07 04:00:00Z], 1800, 6, "America/New_York")

  describe "date/2" do
    test "writes a date as R does, a year unpadded" do
      # label_date()(D("2020-01-01", NA, "2021-06-15")); on the dates -719490, -735265,
      # 3652059 and -719528 days from 1970-01-01; on as.Date(character())
      assert Labels.date([~D[2020-01-01], nil, ~D[2021-06-15]]) ==
               ["2020-01-01", nil, "2021-06-15"]

      dates =
        Enum.map([-719_490, -735_265, 3_652_059, -719_528], fn days ->
          Date.add(~D[1970-01-01], days)
        end)

      assert Labels.date(dates) == ["0-02-08", "-44-11-30", "11968-12-31", "0-01-01"]
      assert Labels.date([]) == []
    end

    test "writes a date at midnight UTC, whatever tz: names" do
      # label_date("%Y-%m-%d %H:%M:%S %Z %z %s")(D("2020-07-01")); "%Y-%m-%d %H:%M %Z" with
      # tz = "America/New_York"
      assert Labels.date([~D[2020-07-01]], format: "%Y-%m-%d %H:%M:%S %Z %z %s") ==
               ["2020-07-01 00:00:00 UTC +0000 1593561600"]

      assert Labels.date([~D[2020-07-01]], [format: "%Y-%m-%d %H:%M %Z"] ++ @new_york) ==
               ["2020-07-01 00:00 UTC"]
    end

    test "shifts a date-time into tz:, UTC unless given" do
      # label_date("%Y-%m-%d %H:%M %Z %z")(NY("2021-03-14 01:30:00", "2021-03-14 03:30:00", NA));
      # the same with tz = "America/New_York"; label_date("%Y-%m-%d %H:%M", tz =
      # "Asia/Kolkata")(U("2020-01-01 00:00", "2020-06-30 20:00"))
      spring =
        [~N[2021-03-14 01:30:00], ~N[2021-03-14 03:30:00]]
        |> Enum.map(fn naive -> in_zone(naive, "America/New_York") end)
        |> Enum.concat([nil])

      format = [format: "%Y-%m-%d %H:%M %Z %z"]

      assert Labels.date(spring, format) ==
               ["2021-03-14 06:30 UTC +0000", "2021-03-14 07:30 UTC +0000", nil]

      assert Labels.date(spring, format ++ @new_york) ==
               ["2021-03-14 01:30 EST -0500", "2021-03-14 03:30 EDT -0400", nil]

      utc = [~U[2020-01-01 00:00:00Z], ~U[2020-06-30 20:00:00Z]]

      assert Labels.date(utc, [format: "%Y-%m-%d %H:%M", tz: "Asia/Kolkata"] ++ @zones) ==
               ["2020-01-01 05:30", "2020-07-01 01:30"]
    end

    test "tells a repeated hour apart only by its zone's abbreviation" do
      # label_date("%H:%M %Z", tz = "America/New_York")(seq(NY("2021-11-07 00:00"), by = "30
      # min", length.out = 6))
      assert Labels.date(fall_back(), [format: "%H:%M %Z"] ++ @new_york) ==
               ["00:00 EDT", "00:30 EDT", "01:00 EDT", "01:30 EDT", "01:00 EST", "01:30 EST"]
    end

    test "writes each conversion R and Calendar share as R does" do
      # label_date("%a %A %b %B %d %m %y %j %H %I %M %S %p %u")(U("2020-03-05 14:07:09"));
      # "%H:%M:%S" on U("2020-01-02 03:04:05.678"); "%%Y is %Y, 100%%" on D("2020-01-01")
      assert Labels.date([~N[2020-03-05 14:07:09]],
               format: "%a %A %b %B %d %m %y %j %H %I %M %S %p %u"
             ) == ["Thu Thursday Mar March 05 03 20 065 14 02 07 09 PM 4"]

      assert Labels.date([~N[2020-01-02 03:04:05.678]], format: "%H:%M:%S") == ["03:04:05"]
      assert Labels.date([~D[2020-01-01]], format: "%%Y is %Y, 100%%") == ["%Y is 2020, 100%"]
    end

    test "writes a naive date-time as it is, its zone UTC, never shifted" do
      # A departure: R writes U("2020-01-01 12:00") in tz = "America/New_York" as "07:00 EST";
      # a NaiveDateTime has no zone to shift from.
      assert Labels.date([~N[2020-01-01 12:00:00]], [format: "%H:%M %Z"] ++ @new_york) ==
               ["12:00 UTC"]
    end

    test "writes %s as the instant's Unix time in every zone" do
      # A departure: label_date("%Y-%m-%d %H:%M %s", tz = "Asia/Kolkata")(as.POSIXct(0, tz =
      # "UTC")) is "1970-01-01 05:30 19800", the wall clock counted as though it were UTC's;
      # label_date("%s") on it is "0".
      kolkata = [format: "%Y-%m-%d %H:%M %s", tz: "Asia/Kolkata"] ++ @zones
      assert Labels.date([~U[1970-01-01 00:00:00Z]], kolkata) == ["1970-01-01 05:30 0"]
      assert Labels.date([~U[1970-01-01 00:00:00Z]], format: "%s") == ["0"]
    end
  end

  describe "date_short/2" do
    test "writes a part where it or a coarser part changed" do
      # label_date_short()(seq(D("2019-11-01"), D("2020-03-01"), by = "month")); by = "year"
      # from D("2018-01-01") to D("2021-01-01"); by = "day" from D("2019-12-29") to
      # D("2020-01-03"); by = "week" from D("2019-12-16") to D("2020-01-20")
      months = Enum.map(-2..2, fn months -> Date.shift(~D[2020-01-01], month: months) end)
      assert Labels.date_short(months) == ["Nov\n2019", "Dec", "Jan\n2020", "Feb", "Mar"]

      years = Enum.map(2018..2021, fn year -> Date.new!(year, 1, 1) end)
      assert Labels.date_short(years) == ["2018", "2019", "2020", "2021"]

      days = Enum.map(0..5, fn day -> Date.add(~D[2019-12-29], day) end)

      assert Labels.date_short(days) ==
               ["29\nDec\n2019", "30", "31", "01\nJan\n2020", "02", "03"]

      weeks = Enum.map(0..5, fn week -> Date.add(~D[2019-12-16], 7 * week) end)

      assert Labels.date_short(weeks) ==
               ["16\nDec\n2019", "23", "30", "06\nJan\n2020", "13", "20"]
    end

    test "compares each break with the one before, in the order given" do
      # label_date_short()(D("2021-03-01", "2020-01-01", "2020-02-01")); D("2020-05-05");
      # D("2020-01-01"); as.Date(character())
      assert Labels.date_short([~D[2021-03-01], ~D[2020-01-01], ~D[2020-02-01]]) ==
               ["Mar\n2021", "Jan\n2020", "Feb"]

      assert Labels.date_short([~D[2020-05-05]]) == ["05\nMay\n2020"]
      assert Labels.date_short([~D[2020-01-01]]) == ["2020"]
      assert Labels.date_short([]) == []
    end

    test "writes every part after a missing break" do
      # label_date_short()(D("2019-12-30", NA, "2020-01-01", "2020-01-02")); D(NA,
      # "2019-12-30", "2020-01-01"); D(NA, NA); D("2020-01-01", NA, "2020-03-01");
      # U("2020-01-01 22:00", NA, "2020-01-02 02:00"); U("2020-01-01 00:00", NA, "2020-02-01
      # 00:00")
      assert Labels.date_short([~D[2019-12-30], nil, ~D[2020-01-01], ~D[2020-01-02]]) ==
               ["30\nDec\n2019", nil, "01\nJan\n2020", "02"]

      assert Labels.date_short([nil, ~D[2019-12-30], ~D[2020-01-01]]) ==
               [nil, "30\nDec\n2019", "01\nJan\n2020"]

      assert Labels.date_short([nil, nil]) == [nil, nil]

      assert Labels.date_short([~D[2020-01-01], nil, ~D[2020-03-01]]) ==
               ["Jan\n2020", nil, "Mar\n2020"]

      assert Labels.date_short([~N[2020-01-01 22:00:00], nil, ~N[2020-01-02 02:00:00]]) ==
               ["22:00\n01\nJan\n2020", nil, "02:00\n02\nJan\n2020"]

      assert Labels.date_short([~N[2020-01-01 00:00:00], nil, ~N[2020-02-01 00:00:00]]) ==
               ["Jan\n2020", nil, "Feb\n2020"]
    end

    test "writes the time unless every break is at midnight, to the minute" do
      # label_date_short()(seq(U("2020-01-01 18:00"), by = "3 hours", length.out = 5));
      # seq(U("2020-01-30"), by = "day", length.out = 4); U("2020-01-01 10:00", "2020-01-01
      # 10:00", "2020-01-01 11:00"); U("2020-01-01", "2021-01-01"); U("2020-01-01 00:00:30",
      # "2020-01-02 00:00:00"); U("2020-01-01 00:30", "2020-01-02 00:30"); U("2020-01-01 05:00",
      # "2020-01-02 00:00")
      hours = naive_series(~N[2020-01-01 18:00:00], 3 * 3600, 5)

      assert Labels.date_short(hours) ==
               ["18:00\n01\nJan\n2020", "21:00", "00:00\n02", "03:00", "06:00"]

      days = naive_series(~N[2020-01-30 00:00:00], 86_400, 4)
      assert Labels.date_short(days) == ["30\nJan\n2020", "31", "01\nFeb", "02"]

      repeated = [~N[2020-01-01 10:00:00], ~N[2020-01-01 10:00:00], ~N[2020-01-01 11:00:00]]
      assert Labels.date_short(repeated) == ["10:00\n01\nJan\n2020", "10:00", "11:00"]

      assert Labels.date_short([~N[2020-01-01 00:00:00], ~N[2021-01-01 00:00:00]]) ==
               ["2020", "2021"]

      assert Labels.date_short([~N[2020-01-01 00:00:30], ~N[2020-01-02 00:00:00]]) ==
               ["01\nJan\n2020", "02"]

      assert Labels.date_short([~N[2020-01-01 00:30:00], ~N[2020-01-02 00:30:00]]) ==
               ["00:30\n01\nJan\n2020", "00:30\n02"]

      assert Labels.date_short([~N[2020-01-01 05:00:00], ~N[2020-01-02 00:00:00]]) ==
               ["05:00\n01\nJan\n2020", "00:00\n02"]
    end

    test "reads what changed on each break's own clock and writes it in tz:" do
      # label_date_short()(seq(NY("2019-12-31 22:00"), by = "1 hour", length.out = 4)); the same
      # with tz = "America/New_York"; seq(NY("2020-01-01 00:00"), by = "day", length.out = 3);
      # tz = "America/New_York" on seq(U("2020-01-01"), by = "day", length.out = 3), and on
      # seq(NY("2021-11-07 00:00"), by = "30 min", length.out = 6)
      assert Labels.date_short(new_year_hours(), @zones) ==
               ["03:00\n01\nJan\n2020", "04:00", "05:00\n01\nJan\n2020", "06:00"]

      assert Labels.date_short(new_year_hours(), @new_york) ==
               ["22:00\n31\nDec\n2019", "23:00", "00:00\n01\nJan\n2020", "01:00"]

      new_york_days = series(~U[2020-01-01 05:00:00Z], 86_400, 3, "America/New_York")
      assert Labels.date_short(new_york_days, @zones) == ["01\nJan\n2020", "02", "03"]

      utc_days = series(~U[2020-01-01 00:00:00Z], 86_400, 3)
      assert Labels.date_short(utc_days, @new_york) == ["31\nDec\n2019", "01", "02"]

      assert Labels.date_short(fall_back(), @new_york) ==
               ["00:00\n07\nNov\n2021", "00:30", "01:00", "01:30", "01:00", "01:30"]
    end

    test "writes a break with no part to write in full, as R's format() does" do
      # label_date_short()(D("2020-01-05", "2020-01-05", "2020-01-06")); D("2020-01-05", NA,
      # "2020-01-05"); rep(NY("2020-01-01"), 2); c(NY("2020-01-01"), seq(NY("2020-01-01 00:00"),
      # by = "day", length.out = 3)); rep(as.POSIXct("2020-01-01", tz = "Asia/Kolkata"), 2);
      # U("2020-01-01 00:00:00.5", "2020-01-01 00:00:00.5"); U("2020-01-01 00:00:30",
      # "2020-01-01 00:00:30"); c(NA, "%b", "%d", "%H:%M") on
      # D("2020-01-01", "2021-01-01"); sep = "/", leading = " " on D("2020-01-05", "2020-01-05")
      assert Labels.date_short([~D[2020-01-05], ~D[2020-01-05], ~D[2020-01-06]]) ==
               ["05\nJan\n2020", "2020-01-05", "06"]

      assert Labels.date_short([~D[2020-01-05], nil, ~D[2020-01-05]]) ==
               ["05\nJan\n2020", nil, "05\nJan\n2020"]

      [new_year | _days] =
        new_york_days = series(~U[2020-01-01 05:00:00Z], 86_400, 3, "America/New_York")

      assert Labels.date_short([new_year, new_year], @zones) == ["2020", "2020-01-01 05:00:00"]

      assert Labels.date_short([new_year | new_york_days], @zones) ==
               ["01\nJan\n2020", "2020-01-01 05:00:00", "02", "03"]

      kolkata = in_zone(~N[2020-01-01 00:00:00], "Asia/Kolkata")
      assert Labels.date_short([kolkata, kolkata], @zones) == ["2019", "2019-12-31 18:30:00"]

      fraction = ~N[2020-01-01 00:00:00.5]
      assert Labels.date_short([fraction, fraction]) == ["2020", "2020-01-01 00:00:00"]

      seconds = ~N[2020-01-01 00:00:30]
      assert Labels.date_short([seconds, seconds]) == ["2020", "2020-01-01 00:00:30"]

      assert Labels.date_short([~D[2020-01-01], ~D[2021-01-01]], format: [year: nil]) ==
               ["2020-01-01", "2021-01-01"]

      assert Labels.date_short([~D[2020-01-05], ~D[2020-01-05]], sep: "/", leading: " ") ==
               [" 5/Jan/2020", "2020-01-05"]
    end

    test "takes each part's format, nil for a part never written" do
      # label_date_short(c("%Y", "%m", "%d", "%H"))(seq(U("2020-01-01 18:00"), by = "3 hours",
      # length.out = 5)); c(NA, "%m", "%d", "%H") on the same; c("%Y", "%B", "%d", "%H:%M"),
      # sep = " ", leading = "" on D("2020-01-05", "2020-01-06", "2020-02-07")
      hours = naive_series(~N[2020-01-01 18:00:00], 3 * 3600, 5)

      assert Labels.date_short(hours, format: [month: "%m", time: "%H"]) ==
               ["18\n01\n01\n2020", "21", "00\n02", "03", "06"]

      assert Labels.date_short(hours, format: [year: nil, month: "%m", time: "%H"]) ==
               ["18\n01\n01", "21", "00\n02", "03", "06"]

      dates = [~D[2020-01-05], ~D[2020-01-06], ~D[2020-02-07]]

      assert Labels.date_short(dates, format: [month: "%B"], sep: " ", leading: "") ==
               ["5 January 2020", "6", "7 February"]
    end

    test "replaces a 0 at the start of each part with leading:, and joins them with sep:" do
      # label_date_short(leading = " ")(D("2020-01-05", "2020-01-06", "2020-02-07"));
      # leading = "" on seq(U("2020-01-01 18:00"), by = "3 hours", length.out = 5); sep = " / "
      # on the same; c("%Y", "%m", "%d", "%H:%M"), leading = " " on D("2020-01-05",
      # "2020-02-06")
      assert Labels.date_short([~D[2020-01-05], ~D[2020-01-06], ~D[2020-02-07]], leading: " ") ==
               [" 5\nJan\n2020", " 6", " 7\nFeb"]

      hours = naive_series(~N[2020-01-01 18:00:00], 3 * 3600, 5)

      assert Labels.date_short(hours, leading: "") ==
               ["18:00\n1\nJan\n2020", "21:00", "0:00\n2", "3:00", "6:00"]

      assert Labels.date_short(hours, sep: " / ") ==
               ["18:00 / 01 / Jan / 2020", "21:00", "00:00 / 02", "03:00", "06:00"]

      assert Labels.date_short([~D[2020-01-05], ~D[2020-02-06]],
               format: [month: "%m"],
               leading: " "
             ) == [" 5\n 1\n2020", " 6\n 2"]
    end

    test "takes sep: and leading: as text, each part on its own" do
      # Departures: R replaces in the joined text, so label_date_short(sep = "", leading =
      # " ")(D("2020-01-05", "2020-01-06", "2020-02-07")) is c(" 5Jan2 2 ", " 6", " 7Feb"), and
      # leading = "\\1" is read as a back reference, writing c("5\nJan\n2020", ...).
      dates = [~D[2020-01-05], ~D[2020-01-06], ~D[2020-02-07]]
      assert Labels.date_short(dates, sep: "", leading: " ") == [" 5Jan2020", " 6", " 7Feb"]
      assert Labels.date_short(dates, leading: "\\1") == ["\\15\nJan\n2020", "\\16", "\\17\nFeb"]
    end

    test "takes dates and date-times together, a date at its midnight" do
      # No R row: R's vectors hold one kind.
      assert Labels.date_short([~D[2020-01-01], ~N[2020-01-02 00:00:00]]) ==
               ["01\nJan\n2020", "02"]

      assert Labels.date_short([~D[2020-01-01], ~N[2020-01-02 10:00:00]]) ==
               ["00:00\n01\nJan\n2020", "10:00\n02"]
    end
  end

  describe "time/2" do
    test "writes a date-time's time of day in tz:, UTC unless given" do
      # label_time()(U("2020-01-01 13:05:09.9", NA)); seq(NY("2019-12-31 22:00"), by = "1
      # hour", length.out = 4); the same with tz = "America/New_York"
      assert Labels.time([~U[2020-01-01 13:05:09.9Z], nil]) == ["13:05:09", nil]

      assert Labels.time(new_year_hours(), @zones) ==
               ["03:00:00", "04:00:00", "05:00:00", "06:00:00"]

      assert Labels.time(new_year_hours(), @new_york) ==
               ["22:00:00", "23:00:00", "00:00:00", "01:00:00"]
    end

    test "writes a time of day as R writes an hms wrapped past midnight" do
      # label_time()(hms::hms(c(0, 3661, 86399, 86400, 90000, -30, NA, 0.5))); "%H:%M" on
      # hms::hms(c(59, 3599.9)); "%I:%M %p" on hms::hms(c(0, 46800)); hms::hms()
      times =
        [~T[00:00:00], ~T[01:01:01], ~T[23:59:59], ~T[00:00:00], ~T[01:00:00], ~T[23:59:30]] ++
          [nil, ~T[00:00:00.5]]

      labels = ["00:00:00", "01:01:01", "23:59:59", "00:00:00", "01:00:00", "23:59:30"]
      assert Labels.time(times) == labels ++ [nil, "00:00:00"]

      assert Labels.time([~T[00:00:59], ~T[00:59:59.9]], format: "%H:%M") == ["00:00", "00:59"]

      assert Labels.time([~T[00:00:00], ~T[13:00:00]], format: "%I:%M %p") == [
               "12:00 AM",
               "01:00 PM"
             ]

      assert Labels.time([]) == []
    end

    test "writes a time of day as it is, never shifted" do
      # A departure: label_time(tz = "America/New_York")(hms::hms(c(0, 3661))) is c("19:00:00",
      # "20:01:01"), an hms read as seconds from midnight UTC; a Time has no zone.
      assert Labels.time([~T[00:00:00], ~T[01:01:01]], @new_york) == ["00:00:00", "01:01:01"]
    end
  end

  describe "a call the date labellers refuse" do
    test "names a break of a kind the labeller does not write" do
      for {function, name, breaks} <- [
            {&Labels.date/1, "Labels.date/2", [~T[01:00:00]]},
            {&Labels.date_short/1, "Labels.date_short/2", [~T[01:00:00]]},
            {&Labels.time/1, "Labels.time/2", [~D[2020-01-01]]},
            {&Labels.date/1, "Labels.date/2", [1]},
            {&Labels.date/1, "Labels.date/2", ["2020-01-01"]},
            {&Labels.time/1, "Labels.time/2", ~T[01:00:00]}
          ] do
        error = assert_raise ArgumentError, fn -> function.(breaks) end
        assert error.message =~ name
        assert error.message =~ inspect(breaks)
      end
    end

    test "names a format Calendar.strftime/3 cannot write, or none" do
      # R's `%e`, `%D` and `%OS3` are not Calendar's; R recycles a vector and reads "" as its
      # default.
      for format <- ["%e", "%D", "%OS3", "", ["%Y", "%m"], nil],
          label <- [
            fn -> Labels.date([~D[2020-01-01]], format: format) end,
            fn -> Labels.time([], format: format) end
          ] do
        error = assert_raise NimbleOptions.ValidationError, label
        assert error.message =~ ":format"
        assert error.message =~ inspect(format)
      end

      for {format, named} <- [
            {[day: "%e"], "%e"},
            {[day: ""], ":day"},
            {[week: "%U"], ":week"},
            {[time: 5], ":time"},
            {"%Y", ":format"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Labels.date_short([], format: format)
          end

        assert error.message =~ named
      end
    end

    test "names the format of a time of day that writes a part of a date" do
      # R writes hms::hms(0) under "%Y-%m-%d" as "1970-01-01".
      for format <- ["%Y-%m-%d", "%d", "%j", "%c"] do
        error =
          assert_raise ArgumentError, fn -> Labels.time([~T[00:00:00]], format: format) end

        assert error.message =~ inspect(format)
      end

      assert Labels.time([~N[1970-01-01 00:00:00]], format: "%Y-%m-%d") == ["1970-01-01"]
    end

    test "names a zone the time zone database cannot read" do
      # R writes tz = "Not/AZone" as UTC under the abbreviation "Not", and tz = "" in the
      # machine's own zone; Elixir's own database knows "Etc/UTC" alone.
      for zone <- ["America/New_York", "UTC"],
          function <- [&Labels.date/2, &Labels.date_short/2, &Labels.time/2] do
        error = assert_raise ArgumentError, fn -> function.([], tz: zone) end
        assert error.message =~ inspect(zone)
        assert error.message =~ "time_zone_database:"
      end

      for zone <- ["Not/AZone", ""] do
        error = assert_raise ArgumentError, fn -> Labels.date([], [tz: zone] ++ @zones) end
        assert error.message =~ inspect(zone)
      end
    end

    test "names a sep: or leading: that is not text" do
      for {name, value} = option <- [sep: nil, leading: nil, leading: 0, sep: ["\n", "/"]] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Labels.date_short([~D[2020-01-01]], [option])
          end

        assert error.message =~ inspect(name)
        assert error.message =~ inspect(value)
      end
    end
  end
end
