# Builds just-the-docs navigation from the repository's existing Markdown files.
module Jekyll
  class ExamplesNavigation < Generator
    safe true
    priority :highest

    CHAPTERS = {
      "chat-webapp" => ["Chat web app", 2],
      "examples/agent_orchestrators" => ["Agent orchestrators", 3],
      "examples/agents" => ["Agents", 4],
      "examples/catalog_mcp_servers" => ["Catalog MCP servers", 5],
      "examples/code_mcp_servers" => ["Code MCP servers", 6],
      "examples/container_mcp_servers" => ["Container MCP servers", 7],
      "examples/custom_sources" => ["Custom sources", 8],
      "helm-charts" => ["Helm charts", 9]
    }.freeze

    REFERENCE_FILES = %w[
      CONTRIBUTING.md
      INSTRUCTIONS.md
      SECURITY.md
      SUPPORT.md
      chat-webapp/THIRDPARTY.md
    ].freeze

    def generate(site)
      load_markdown_pages(site)
      pages = site.pages.select { |page| markdown?(page.path) }
      pages_by_path = pages.to_h { |page| [normalize(page.path), page] }

      pages.each do |page|
        path = normalize(page.path)
        page.data["layout"] ||= "default"
        page.data["title"] ||= title_for(page, path)
        page.data["permalink"] ||= permalink_for(path)

        if path == "README.md"
          page.data.merge!("layout" => "home", "title" => "Overview", "nav_order" => 1, "permalink" => "/")
        elsif path == "docs/reference.md"
          page.data.merge!("title" => "Reference", "nav_order" => 10, "has_children" => true, "permalink" => "/reference/")
        elsif REFERENCE_FILES.include?(path)
          page.data.merge!("parent" => "Reference", "nav_order" => reference_order(path))
        else
          assign_chapter(page, path, pages_by_path)
        end
      end
    end

    private

    def load_markdown_pages(site)
      existing = site.pages.map { |page| normalize(page.path) }.to_h { |path| [path, true] }
      ignored_prefixes = %w[_site/ vendor/ .jekyll-cache/].freeze

      Dir.glob(File.join(site.source, "**", "*.{md,markdown}"), File::FNM_CASEFOLD).sort.each do |filename|
        path = normalize(filename.delete_prefix("#{site.source}/"))
        next if existing[path] || ignored_prefixes.any? { |prefix| path.start_with?(prefix) }

        page = PageWithoutAFile.new(site, site.source, File.dirname(path), File.basename(path))
        page.content = File.read(filename, encoding: "UTF-8")
        page.data = {}
        site.pages << page
        existing[path] = true
      end

      site.static_files.reject! { |file| markdown?(file.relative_path) }
    end

    def markdown?(path)
      %w[.md .markdown].include?(File.extname(path).downcase)
    end

    def normalize(path)
      path.tr("\\", "/")
    end

    def title_for(page, path)
      heading = page.content[/^#\s+(.+)$/, 1]
      title = heading || File.basename(path, File.extname(path)).tr("_-", " ")
      title.gsub(/[`*_]/, "").gsub(/\[([^\]]+)\]\([^\)]+\)/, '\\1').strip
    end

    def permalink_for(path)
      return "/" if path == "README.md"

      clean = path.sub(%r{/README\.md$}i, "/").sub(/\.md$/i, "/")
      "/#{clean}".gsub(%r{/+}, "/")
    end

    def assign_chapter(page, path, pages_by_path)
      root, config = CHAPTERS.find { |prefix, _| path == "#{prefix}/README.md" || path.start_with?("#{prefix}/") }
      return unless root

      chapter_title, order = config
      if path == "#{root}/README.md"
        page.data.merge!("title" => chapter_title, "nav_order" => order, "has_children" => descendants?(root, pages_by_path))
        return
      end

      relative = path.delete_prefix("#{root}/")
      segments = relative.split("/")
      page.data["nav_order"] ||= page.data["title"].downcase

      if segments.length > 2
        parent_path = "#{root}/#{segments[0..-2].join("/")}/README.md"
        parent_page = pages_by_path[parent_path]
        if parent_page
          parent_page.data["title"] ||= title_for(parent_page, parent_path)
          parent_page.data["has_children"] = true
          page.data["parent"] = parent_page.data["title"]
          page.data["grand_parent"] = chapter_title
          return
        end
      end

      page.data["parent"] = chapter_title
    end

    def descendants?(root, pages_by_path)
      pages_by_path.keys.any? { |path| path.start_with?("#{root}/") && path != "#{root}/README.md" }
    end

    def reference_order(path)
      REFERENCE_FILES.index(path).to_i + 1
    end
  end

  module ProjectPageLinks
    def self.rewrite(output, baseurl)
      return output unless output

      output = output.gsub(/href="((?![a-z]+:|\/\/)[^"?#]*)(README)?\.(?:md|markdown)([?#][^"]*)?"/i) do
        path = Regexp.last_match(1)
        suffix = Regexp.last_match(3).to_s
        target = Regexp.last_match(2) ? path : "#{path}/"
        %(href="#{target}#{suffix}")
      end

      return output if baseurl.to_s.empty?

      base = baseurl.chomp("/")
      output.gsub(/(href|src)="(\/[^"#]*)"/) do |match|
        attribute = Regexp.last_match(1)
        target = Regexp.last_match(2)
        next match if target == base || target.start_with?("#{base}/")

        %(#{attribute}="#{base}#{target}")
      end
    end
  end

  Hooks.register [:pages, :documents], :post_render do |item|
    item.output = ProjectPageLinks.rewrite(item.output, item.site.config["baseurl"])
  end
end
