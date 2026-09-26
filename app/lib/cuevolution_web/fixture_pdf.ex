defmodule CuevolutionWeb.FixturePdf do
  @moduledoc false

  alias Cuevolution.Competitions

  @page_width 612
  @page_height 792
  @margin 36
  @navy {13, 12, 34}
  @red {227, 34, 25}
  @blue {38, 35, 112}
  @light {247, 248, 251}
  @muted {110, 109, 122}

  def render(fixtures, venue_name, stage_name) do
    image_data = [load_image("SP-pool-blue-logo.png"), load_image("cuevolution-logo.png")]

    fixtures
    |> Enum.chunk_every(5)
    |> case do
      [] -> [[]]
      pages -> pages
    end
    |> Enum.map(&page_content(&1, venue_name, stage_name))
    |> build_pdf(image_data)
  end

  defp page_content(fixtures, venue_name, stage_name) do
    rows = fixtures |> Enum.with_index() |> Enum.map(&fixture_row(elem(&1, 0), elem(&1, 1)))
    [header(venue_name, stage_name), table_header(), rows] |> IO.iodata_to_binary()
  end

  defp header(venue_name, stage_name) do
    [
      "q\n",
      color(@light, "rg"),
      "0 0 #{@page_width} #{@page_height} re f\n",
      color(@light, "rg"),
      "0 700 #{@page_width} 92 re f\n",
      "q 102 0 0 66 42 713 cm /Im1 Do Q\n",
      "q 116 0 0 24 454 747 cm /Im2 Do Q\n",
      color(@navy, "rg"),
      "BT /F1 14 Tf 171 750 Td (",
      text("Sportpesa National Pool Circuit"),
      ") Tj ET\n",
      color(@muted, "rg"),
      "BT /F1 8 Tf 306 728 Td (",
      text("OFFICIAL FIXTURE SHEET"),
      ") Tj ET\n",
      color(@navy, "rg"),
      "BT /F1 8 Tf 170 672 Td (",
      text("VENUE"),
      ") Tj ET\n",
      color({20, 19, 40}, "rg"),
      "BT /F1 13 Tf 170 653 Td (",
      text(venue_name),
      ") Tj ET\n",
      color(@muted, "rg"),
      "BT /F1 8 Tf 170 635 Td (",
      text("STAGE"),
      ") Tj ET\n",
      color({20, 19, 40}, "rg"),
      "BT /F1 11 Tf 170 618 Td (",
      text(stage_name),
      ") Tj ET\n",
      "Q\n"
    ]
  end

  defp table_header do
    [
      color(@red, "rg"),
      "#{@margin} 574 540 28 re f\n",
      color({255, 255, 255}, "rg"),
      "BT /F1 7 Tf 46 584 Td (MATCH) Tj 70 0 Td (SCHEDULE) Tj 92 0 Td (GROUP / PLAYER A) Tj 145 0 Td (PLAYER B) Tj 145 0 Td (STATUS) Tj ET\n",
      color(@blue, "RG"),
      "1 w 36 574 m 576 574 l S\n"
    ]
  end

  defp fixture_row(fixture, index) do
    y = 574 - (index + 1) * 88
    background = if rem(index, 2) == 0, do: {255, 255, 255}, else: @light
    participant_a = participant_label(fixture.participant_a)
    participant_b = participant_label(fixture.participant_b)
    score = fixture_score(fixture)

    [
      color(background, "rg"),
      "36 #{y} 540 88 re f\n",
      color({220, 221, 228}, "RG"),
      "0.7 w 36 #{y} m 576 #{y} l S\n",
      color(@navy, "rg"),
      "BT /F1 8 Tf 46 #{y + 68} Td (",
      text(fixture.match_id || "Fixture"),
      ") Tj ET\n",
      color(@muted, "rg"),
      "BT /F1 7 Tf 116 #{y + 68} Td (",
      text(fixture_schedule(fixture)),
      ") Tj ET\n",
      color(@navy, "rg"),
      "BT /F1 8 Tf 208 #{y + 68} Td (",
      text(fixture_group(fixture)),
      ") Tj ET\n",
      "BT /F1 8 Tf 208 #{y + 49} Td (",
      text(participant_a),
      ") Tj ET\n",
      color(score_color(score), "rg"),
      "BT /F1 8 Tf 208 #{y + 31} Td (",
      text(score_value(score, 0)),
      ") Tj ET\n",
      color(@navy, "rg"),
      "BT /F1 8 Tf 353 #{y + 49} Td (",
      text(participant_b),
      ") Tj ET\n",
      color(score_color(score), "rg"),
      "BT /F1 8 Tf 353 #{y + 31} Td (",
      text(score_value(score, 1)),
      ") Tj ET\n",
      color(status_color(fixture.status), "rg"),
      "BT /F1 7 Tf 498 #{y + 49} Td (",
      text(String.upcase(fixture.status || "scheduled")),
      ") Tj ET\n",
      color(@muted, "rg"),
      "BT /F1 6 Tf 498 #{y + 31} Td (GROUP) Tj ET\n"
    ]
  end

  defp participant_label(%{player: %{first_name: first_name, last_name: last_name}}),
    do: shorten("#{first_name} #{last_name}", 23)

  defp participant_label(%{team: %{name: name}}), do: shorten(name, 23)
  defp participant_label(participant), do: shorten(Competitions.participant_name(participant), 23)

  defp fixture_score(%{
         result: %{score: %{"participant_a_frames" => a, "participant_b_frames" => b}}
       }),
       do: {a, b}

  defp fixture_score(_fixture), do: nil

  defp score_value({a, _b}, 0), do: "(#{a})"
  defp score_value({_a, b}, 1), do: "(#{b})"
  defp score_value(_score, _index), do: ""

  defp score_color(nil), do: @muted
  defp score_color(_score), do: {14, 106, 48}

  defp shorten(value, limit) do
    value = to_string(value)
    if String.length(value) > limit, do: String.slice(value, 0, limit - 3) <> "...", else: value
  end

  defp status_color(status) when status in ["completed", "verified"], do: {14, 106, 48}
  defp status_color("postponed"), do: @red
  defp status_color(_status), do: @blue

  defp fixture_schedule(%{scheduled_at: nil}), do: "Play by deadline"

  defp fixture_schedule(fixture) do
    fixture |> Competitions.fixture_time_in_eat() |> Calendar.strftime("%b %-d, %Y %H:%M")
  end

  defp fixture_group(%{round: %{group: %{name: name}}}) when is_binary(name), do: name
  defp fixture_group(_fixture), do: "Knockout"

  defp color({red, green, blue}, operator),
    do: "#{red / 255} #{green / 255} #{blue / 255} #{operator}\n"

  defp text(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace(~r/[^\x20-\x7E]/u, "?")
  end

  defp build_pdf(page_contents, image_data) do
    page_ids = Enum.with_index(page_contents, fn _content, index -> 6 + index * 2 end)

    image_objects =
      image_data
      |> Enum.with_index(4)
      |> Enum.map(fn {image, id} -> {id, image_object(image)} end)

    page_objects =
      page_contents
      |> Enum.with_index()
      |> Enum.flat_map(fn {content, index} ->
        page_id = Enum.at(page_ids, index)
        content_id = page_id + 1

        [
          {page_id,
           "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{@page_width} #{@page_height}] " <>
             "/Resources << /Font << /F1 1 0 R >> /XObject << /Im1 4 0 R /Im2 5 0 R >> >> " <>
             "/Contents #{content_id} 0 R >>"},
          {content_id, "<< /Length #{byte_size(content)} >>\nstream\n#{content}endstream"}
        ]
      end)

    objects = [
      {1, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"},
      {2,
       "<< /Type /Pages /Kids [#{Enum.map_join(page_ids, " ", &"#{&1} 0 R")} ] /Count #{length(page_ids)} >>"},
      {3, "<< /Type /Catalog /Pages 2 0 R >>"}
      | image_objects ++ page_objects
    ]

    header = <<"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n">>

    {body, offsets, _position} =
      Enum.reduce(objects, {header, [{0, 0}], byte_size(header)}, fn {id, object},
                                                                     {pdf, offsets, position} ->
        rendered = IO.iodata_to_binary(["#{id} 0 obj\n", object, "\nendobj\n"])
        {pdf <> rendered, offsets ++ [{id, position}], position + byte_size(rendered)}
      end)

    xref_offset = byte_size(body)
    xref = "xref\n0 #{length(objects) + 1}\n0000000000 65535 f \n"

    xref =
      xref <>
        Enum.map_join(Enum.sort_by(offsets, &elem(&1, 0)) |> Enum.drop(1), "", fn {_id, offset} ->
          "#{String.pad_leading(Integer.to_string(offset), 10, "0")} 00000 n \n"
        end)

    body <>
      xref <>
      "trailer\n<< /Size #{length(objects) + 1} /Root 3 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
  end

  defp load_image(filename) do
    path = Path.join(:code.priv_dir(:cuevolution), "static/images/#{filename}")
    path |> File.read!() |> decode_png()
  end

  defp image_object(%{width: width, height: height, data: data}) do
    compressed = :zlib.compress(data)

    [
      "<< /Type /XObject /Subtype /Image /Width #{width} /Height #{height} ",
      "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode ",
      "/Length #{byte_size(compressed)} >>\nstream\n",
      compressed,
      "\nendstream"
    ]
  end

  defp decode_png(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>) do
    {width, height, compressed} = png_chunks(rest, nil, nil, [])
    raw = :zlib.uncompress(IO.iodata_to_binary(Enum.reverse(compressed)))
    {rgb, _previous} = decode_rows(raw, width, height, <<>>, [])
    %{width: width, height: height, data: IO.iodata_to_binary(Enum.reverse(rgb))}
  end

  defp png_chunks(
         <<length::32, "IHDR", data::binary-size(length), _crc::32, rest::binary>>,
         _,
         _,
         ids
       ) do
    <<width::32, height::32, 8, 6, _rest::binary>> = data
    png_chunks(rest, width, height, ids)
  end

  defp png_chunks(
         <<length::32, "IDAT", data::binary-size(length), _crc::32, rest::binary>>,
         width,
         height,
         ids
       ),
       do: png_chunks(rest, width, height, [data | ids])

  defp png_chunks(<<_length::32, "IEND", _crc::32, _rest::binary>>, width, height, ids),
    do: {width, height, ids}

  defp png_chunks(
         <<length::32, _type::binary-size(4), _data::binary-size(length), _crc::32,
           rest::binary>>,
         width,
         height,
         ids
       ),
       do: png_chunks(rest, width, height, ids)

  defp decode_rows(<<>>, _width, _height, _previous, rows), do: {rows, <<>>}

  defp decode_rows(raw, width, height, previous, rows) when height > 0 do
    <<filter, row::binary-size(width * 4), rest::binary>> = raw
    decoded = unfilter(row, previous, filter, 4, <<>>)
    decode_rows(rest, width, height - 1, decoded, [to_rgb(decoded) | rows])
  end

  defp unfilter(<<>>, _previous, _filter, _bpp, output), do: output

  defp unfilter(<<value, rest::binary>>, previous, filter, bpp, output) do
    index = byte_size(output)
    left = if index >= bpp, do: :binary.at(output, index - bpp), else: 0
    up = if byte_size(previous) > index, do: :binary.at(previous, index), else: 0

    upper_left =
      if index >= bpp and byte_size(previous) > index - bpp,
        do: :binary.at(previous, index - bpp),
        else: 0

    reconstructed =
      case filter do
        0 -> value
        1 -> rem(value + left, 256)
        2 -> rem(value + up, 256)
        3 -> rem(value + div(left + up, 2), 256)
        4 -> rem(value + paeth(left, up, upper_left), 256)
      end

    unfilter(rest, previous, filter, bpp, <<output::binary, reconstructed>>)
  end

  defp paeth(left, up, upper_left) do
    p = left + up - upper_left
    pa = abs(p - left)
    pb = abs(p - up)
    pc = abs(p - upper_left)
    if pa <= pb and pa <= pc, do: left, else: if(pb <= pc, do: up, else: upper_left)
  end

  defp to_rgb(<<>>), do: <<>>

  defp to_rgb(<<red, green, blue, alpha, rest::binary>>) do
    alpha = alpha / 255

    <<round(red * alpha + 255 * (1 - alpha)), round(green * alpha + 255 * (1 - alpha)),
      round(blue * alpha + 255 * (1 - alpha)), to_rgb(rest)::binary>>
  end
end
