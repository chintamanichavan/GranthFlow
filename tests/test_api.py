from __future__ import annotations

from pathlib import Path


def _upload(client, epub_path: Path):
    with open(epub_path, "rb") as f:
        return client.post(
            "/upload",
            files={"file": (epub_path.name, f, "application/epub+zip")},
            follow_redirects=False,
        )


def test_upload_redirects_and_lists_book(client, epub_factory):
    r = _upload(client, epub_factory(title="Alpha", author="Ada"))
    assert r.status_code == 303
    home = client.get("/")
    assert home.status_code == 200
    assert "Alpha" in home.text
    assert "Ada" in home.text


def test_invalid_epub_rejected(client, tmp_path):
    bogus = tmp_path / "bad.epub"
    bogus.write_bytes(b"not actually an epub")
    r = _upload(client, bogus)
    assert r.status_code == 400


def test_book_detail_and_file_download(client, epub_factory):
    _upload(client, epub_factory(title="Beta"))
    detail = client.get("/book/1")
    assert detail.status_code == 200
    assert "Beta" in detail.text
    f = client.get("/book/1/book.epub")
    assert f.status_code == 200
    assert f.headers["content-type"] == "application/epub+zip"


def test_cover_present_and_absent(client, epub_factory):
    _upload(client, epub_factory(title="WithCover", with_cover=True))
    _upload(client, epub_factory(title="NoCover", with_cover=False))
    assert client.get("/book/1/cover").status_code == 200
    assert client.get("/book/2/cover").status_code == 404


def test_highlight_crud_roundtrip(client, epub_factory):
    _upload(client, epub_factory())
    create = client.post(
        "/book/1/highlight",
        json={"cfi": "epubcfi(/6/4!/4/2)", "text": "hello world",
              "color": "green", "note": "first one", "tags": ["intro", "important"]},
    )
    assert create.status_code == 200, create.text
    hl = create.json()
    assert hl["color"] == "green"
    assert hl["note"] == "first one"
    assert hl["tags"] == ["important", "intro"]

    listing = client.get("/book/1/highlights").json()
    assert len(listing) == 1 and listing[0]["id"] == hl["id"]

    upd = client.patch(
        f"/highlight/{hl['id']}",
        json={"color": "pink", "note": "updated", "tags": ["zeta"]},
    )
    assert upd.status_code == 200
    assert upd.json()["color"] == "pink"
    assert upd.json()["note"] == "updated"
    assert upd.json()["tags"] == ["zeta"]

    rm = client.delete(f"/highlight/{hl['id']}")
    assert rm.status_code == 200
    assert client.get("/book/1/highlights").json() == []


def test_save_location(client, epub_factory):
    _upload(client, epub_factory())
    r = client.post("/book/1/location", json={"cfi": "epubcfi(/6/12)"})
    assert r.status_code == 200
    # surfaced via reader page (rendered into JS)
    reader = client.get("/book/1/read")
    assert "epubcfi(/6/12)" in reader.text


def test_export_md_and_json(client, epub_factory):
    _upload(client, epub_factory(title="Gamma", author="Grace"))
    client.post("/book/1/highlight", json={
        "cfi": "epubcfi(/6/4!/4/2)", "text": "quoted bit", "color": "yellow",
        "note": "n", "tags": ["t1"],
    })
    md = client.get("/book/1/export.md")
    assert md.status_code == 200
    assert "# Gamma" in md.text
    assert "Grace" in md.text
    assert "> quoted bit" in md.text
    assert "#t1" in md.text

    js = client.get("/book/1/export.json")
    assert js.status_code == 200
    body = js.json()
    assert body["book"]["title"] == "Gamma"
    assert len(body["highlights"]) == 1
    assert body["highlights"][0]["text"] == "quoted bit"


def test_delete_book_cascades_highlights(client, epub_factory):
    _upload(client, epub_factory())
    client.post("/book/1/highlight", json={
        "cfi": "epubcfi(/6/4)", "text": "x", "color": "yellow", "tags": [],
    })
    assert len(client.get("/book/1/highlights").json()) == 1

    r = client.post("/book/1/delete", follow_redirects=False)
    assert r.status_code == 303
    assert client.get("/book/1").status_code == 404
    assert client.get("/book/1/highlights").status_code == 404


def test_404_for_unknown_book(client):
    assert client.get("/book/999").status_code == 404
    assert client.get("/book/999/book.epub").status_code == 404
    assert client.get("/book/999/cover").status_code == 404
