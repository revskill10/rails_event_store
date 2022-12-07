# frozen_string_literal: true

module DocumentationHelper
  def current_source_file
    current_page.source_file.gsub(Dir.pwd, "")
  end

  def current_source_file_name
    File.basename(current_source_file)
  end

  def page_title
    current_page.data.title
  end

  def rubydoc_link(gem)
    link_to gem, "https://www.rubydoc.info/gems/#{gem}"
  end

  def edit_github_link
    link_to "Edit this page on GitHub",
            File.join(github_url, "blob/master/railseventstore.org", current_source_file),
            class: css_classes
  end

  def sidebar_link_to(name, url)
    current_link_to(
      name,
      url,
      class: %w[
        block
        w-full
        pl-3.5
        before:pointer-events-none
        before:absolute
        before:-left-1
        before:top-1/2
        before:h-1.5
        before:w-1.5
        before:-translate-y-1/2
        before:rounded-full
        text-slate-500
        before:hidden
        before:bg-slate-300
        hover:text-slate-600
        hover:before:block
        bg-none
        font-normal
      ]
    )
  end
end
