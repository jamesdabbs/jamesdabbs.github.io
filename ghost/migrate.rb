require 'date'
require 'json'
require 'pry'
require 'yaml'

db_path = ARGV.shift || File.expand_path("../ghost.json", __FILE__)
db = JSON.parse(File.read db_path)["db"].first

data, meta = db["data"], db["meta"]

posts, tags, post_tags = %w(posts tags posts_tags).map { |k| data.fetch k }

posts.each do |p|
  next if p["page"] == 1 # Will port / re-write these manually

  tags = ["test", "thing", "Thing with spaces in it"]

  date = DateTime.parse p.fetch "published_at"
  file_name = "#{date.strftime '%Y-%m-%d'}-#{p.fetch 'slug'}.md"
  file_path = File.join "_posts", file_name
  File.open file_path, "w" do |f|
    f.puts "---"
    f.puts "layout: post"
    f.puts "title: '#{p.fetch 'title'}'"
    f.puts "date: #{date.strftime '%Y-%m-%d %H:%M:%S'}"
    if tags.any?
      f.puts "tags:"
      tags.each { |t| f.puts "- '#{t}'" }
    end
    f.puts "image: #{p['image']}" if p["image"]
    f.puts "---"

    markdown = p.fetch("markdown").gsub(/```lang-(\w+)/) { "```#{$1}" }
    f.puts markdown
  end
end
