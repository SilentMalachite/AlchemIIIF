defmodule AlchemIiif.SearchTest do
  use AlchemIiif.DataCase, async: true

  alias AlchemIiif.Search
  import AlchemIiif.Factory

  # テストデータのセットアップヘルパー
  defp create_test_images do
    pdf = insert_pdf_source()

    img1 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        caption: "第1図 縄文土器出土状況",
        label: "fig-1-1",
        site: "吉野ヶ里町遺跡",
        period: "縄文時代",
        artifact_type: "土器",
        material: "粘土",
        status: "published",
        ptif_path: "/path/to/test1.tif"
      })

    img2 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 2,
        caption: "第2図 弥生時代の銅鉛",
        label: "fig-2-1",
        site: "静岡市登呂遺跡",
        period: "弥生時代",
        artifact_type: "銅鉛",
        material: "青銅",
        status: "published",
        ptif_path: "/path/to/test2.tif"
      })

    img3 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 3,
        caption: "第3図 下書きの図版",
        label: "fig-3-1",
        site: "吉野ヶ里町遺跡",
        period: "縄文時代",
        artifact_type: "石器",
        material: "黒曜石",
        status: "draft",
        ptif_path: "/path/to/test3.tif"
      })

    %{img1: img1, img2: img2, img3: img3}
  end

  describe "search_images/2" do
    test "PTIF ありの全画像を返す（フィルターなし）" do
      %{img1: img1, img2: img2, img3: img3} = create_test_images()

      results = Search.search_images()
      ids = Enum.map(results, & &1.id)

      assert img1.id in ids
      assert img2.id in ids
      assert img3.id in ids
    end

    test "PTIF なしの画像を除外する" do
      _no_ptif = insert_extracted_image(%{ptif_path: nil, status: "published"})

      results = Search.search_images()
      assert Enum.empty?(results)
    end

    test "テキスト検索でキャプションにマッチする" do
      create_test_images()

      results = Search.search_images("縄文土器")
      assert results != []
      assert Enum.any?(results, &(&1.label == "fig-1-1"))
    end

    test "テキスト検索でラベルにマッチする" do
      create_test_images()

      results = Search.search_images("fig-2-1")
      assert results != []
      assert Enum.any?(results, &(&1.label == "fig-2-1"))
    end

    test "テキスト検索で遺跡名にマッチする" do
      create_test_images()

      results = Search.search_images("静岡市登呂遺跡")
      assert results != []
      assert Enum.any?(results, &(&1.site == "静岡市登呂遺跡"))
    end

    test "site フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"site" => "吉野ヶ里町遺跡"})
      assert Enum.all?(results, &(&1.site == "吉野ヶ里町遺跡"))
    end

    test "period フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"period" => "弥生時代"})
      assert length(results) == 1
      assert hd(results).period == "弥生時代"
    end

    test "artifact_type フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"artifact_type" => "土器"})
      assert Enum.all?(results, &(&1.artifact_type == "土器"))
    end

    test "複数フィルターの組み合わせで絞り込みできる" do
      create_test_images()

      results =
        Search.search_images("", %{
          "site" => "吉野ヶ里町遺跡",
          "period" => "縄文時代"
        })

      assert Enum.all?(results, fn img ->
               img.site == "吉野ヶ里町遺跡" and img.period == "縄文時代"
             end)
    end

    test "空文字列のフィルターは無視される" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results_with_empty = Search.search_images("", %{"site" => ""})
      results_without = Search.search_images()

      assert length(results_with_empty) == length(results_without)
    end

    test "nil のフィルターは無視される" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results_with_nil = Search.search_images("", %{"site" => nil})
      results_without = Search.search_images()

      assert length(results_with_nil) == length(results_without)
    end
  end

  describe "search_published_images/2" do
    test "published 画像のみを返す" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results = Search.search_published_images()
      assert Enum.all?(results, &(&1.status == "published"))
    end

    test "draft 画像を含まない" do
      %{img3: img3} = create_test_images()

      results = Search.search_published_images()
      ids = Enum.map(results, & &1.id)
      refute img3.id in ids
    end

    test "テキスト検索が published 画像にのみ適用される" do
      create_test_images()

      results = Search.search_published_images("吉野ヶ里")
      assert Enum.all?(results, &(&1.status == "published"))
    end
  end

  describe "list_filter_options/0" do
    test "利用可能なフィルターオプションを返す" do
      create_test_images()

      options = Search.list_filter_options()
      assert is_list(options.sites)
      assert is_list(options.periods)
      assert is_list(options.artifact_types)
      assert is_list(options.materials)
    end

    test "データがない場合は空リストを返す" do
      options = Search.list_filter_options()
      assert options.sites == []
      assert options.periods == []
      assert options.artifact_types == []
      assert options.materials == []
    end

    test "DISTINCT な値のみを返す" do
      create_test_images()

      options = Search.list_filter_options()
      # 吉野ヶ里町遺跡は2回登録されているが、1回のみ出力
      assert Enum.count(options.sites, &(&1 == "吉野ヶ里町遺跡")) == 1
    end

    test "materials が取得できる" do
      _images = create_test_images()
      options = Search.list_filter_options()
      assert is_list(options.materials)
      assert "粘土" in options.materials
      assert "青銅" in options.materials
    end
  end

  describe "list_filter_options/1 published_only" do
    test "published_only: true は公開済み画像の値のみ返す" do
      create_test_images()

      options = Search.list_filter_options(published_only: true)

      # draft の img3 の遺跡「吉野ヶ里町遺跡」は img1(published) にもあるので含まれる
      assert "吉野ヶ里町遺跡" in options.sites
      assert "静岡市登呂遺跡" in options.sites

      # draft のみに存在する artifact_type「石器」は除外される
      refute "石器" in options.artifact_types
      # published の artifact_type は含まれる
      assert "土器" in options.artifact_types
      assert "銅鉛" in options.artifact_types
    end

    test "ptif_path が nil の published 画像は除外される" do
      pdf = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        caption: "PTIF未生成",
        label: "fig-90-1",
        site: "奈良市未生成遺跡",
        period: "古墳時代",
        artifact_type: "埴輪",
        status: "published",
        ptif_path: nil
      })

      options = Search.list_filter_options(published_only: true)

      refute "奈良市未生成遺跡" in options.sites
      refute "古墳時代" in options.periods
      refute "埴輪" in options.artifact_types
    end

    test "ptif_path が空文字の published 画像は除外される" do
      pdf = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        caption: "PTIF空文字",
        label: "fig-91-1",
        site: "京都市空文字遺跡",
        period: "平安時代",
        artifact_type: "瓦",
        status: "published",
        ptif_path: ""
      })

      options = Search.list_filter_options(published_only: true)

      refute "京都市空文字遺跡" in options.sites
      refute "平安時代" in options.periods
      refute "瓦" in options.artifact_types
    end

    test "published_only なしの既存動作は変わらない" do
      create_test_images()

      options = Search.list_filter_options()

      # draft の img3 の値も含まれる
      assert "石器" in options.artifact_types
      assert "吉野ヶ里町遺跡" in options.sites
    end

    test "draft の material は published_only で除外される" do
      _images = create_test_images()
      options = Search.list_filter_options(published_only: true)
      assert "粘土" in options.materials
      assert "青銅" in options.materials
      refute "黒曜石" in options.materials
    end
  end

  describe "search_images/2 material フィルター" do
    test "material を指定すると該当レコードのみ返る" do
      %{img1: img1} = create_test_images()
      results = Search.search_images("", %{"material" => "粘土"})
      ids = Enum.map(results, & &1.id)
      assert img1.id in ids
      assert length(ids) == 1
    end

    test "material が nil の場合は全件返る" do
      %{img1: img1, img2: img2} = create_test_images()
      results = Search.search_images("", %{"material" => nil})
      ids = Enum.map(results, & &1.id)
      assert img1.id in ids
      assert img2.id in ids
    end

    test "存在しない material を指定すると空配列が返る" do
      _images = create_test_images()
      results = Search.search_images("", %{"material" => "ダイヤモンド"})
      assert results == []
    end
  end

  defp create_site_code_test_images do
    pdf_niigata = insert_pdf_source(%{site_code: "15206-27"})
    pdf_tokyo = insert_pdf_source(%{site_code: "13101-05"})
    pdf_no_code = insert_pdf_source()

    img_niigata =
      insert_extracted_image(%{
        pdf_source_id: pdf_niigata.id,
        page_number: 1,
        status: "published",
        ptif_path: "/tmp/sc1.tif"
      })

    img_tokyo =
      insert_extracted_image(%{
        pdf_source_id: pdf_tokyo.id,
        page_number: 1,
        status: "published",
        ptif_path: "/tmp/sc2.tif"
      })

    img_no_code =
      insert_extracted_image(%{
        pdf_source_id: pdf_no_code.id,
        page_number: 1,
        status: "published",
        ptif_path: "/tmp/sc3.tif"
      })

    %{img_niigata: img_niigata, img_tokyo: img_tokyo, img_no_code: img_no_code}
  end

  describe "search_images/2 site_code 前方一致フィルター" do
    test "都道府県コード2桁で前方一致検索できる" do
      %{img_niigata: img_niigata, img_tokyo: img_tokyo} = create_site_code_test_images()
      results = Search.search_images("", %{"site_code" => "15"})
      ids = Enum.map(results, & &1.id)
      assert img_niigata.id in ids
      refute img_tokyo.id in ids
    end

    test "市区町村コードまで指定して絞り込める" do
      %{img_niigata: img_niigata} = create_site_code_test_images()
      results = Search.search_images("", %{"site_code" => "15206"})
      ids = Enum.map(results, & &1.id)
      assert img_niigata.id in ids
      assert length(ids) == 1
    end

    test "マッチしないコードでは空配列が返る" do
      _images = create_site_code_test_images()
      results = Search.search_images("", %{"site_code" => "99"})
      assert results == []
    end

    test "空文字の場合は全件返る" do
      %{img_niigata: img_niigata, img_tokyo: img_tokyo, img_no_code: img_no_code} =
        create_site_code_test_images()

      results = Search.search_images("", %{"site_code" => ""})
      ids = Enum.map(results, & &1.id)
      assert img_niigata.id in ids
      assert img_tokyo.id in ids
      assert img_no_code.id in ids
    end

    test "LIKE インジェクション文字がエスケープされる" do
      _images = create_site_code_test_images()
      # "15%" should be treated as literal "15%" not as "15<anything>"
      results = Search.search_images("", %{"site_code" => "15%"})
      assert results == []
    end
  end

  describe "count_results/2" do
    test "全結果件数を返す" do
      create_test_images()

      count = Search.count_results()
      assert count == 3
    end

    test "テキスト検索の結果件数を返す" do
      create_test_images()

      count = Search.count_results("静岡市登呂遺跡")
      assert count >= 1
    end

    test "フィルター適用時の結果件数を返す" do
      create_test_images()

      count = Search.count_results("", %{"period" => "弥生時代"})
      assert count == 1
    end
  end
end
