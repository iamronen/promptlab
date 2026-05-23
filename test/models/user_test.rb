require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
  end

  test "display_label falls back to email when display_name is blank" do
    @user.display_name = nil
    assert_equal @user.email, @user.display_label
  end

  test "display_label uses display_name when present" do
    @user.display_name = "Alice"
    assert_equal "Alice", @user.display_label
  end

  test "strips whitespace from display_name" do
    @user.display_name = "  Alice  "
    @user.valid?
    assert_equal "Alice", @user.display_name
  end

  test "blank display_name becomes nil after strip" do
    @user.display_name = "   "
    @user.valid?
    assert_nil @user.display_name
  end

  test "rejects display_name longer than maximum length" do
    @user.display_name = "a" * (User::DISPLAY_NAME_MAX_LENGTH + 1)
    assert_not @user.valid?
    assert_includes @user.errors[:display_name], "is too long (maximum is #{User::DISPLAY_NAME_MAX_LENGTH} characters)"
  end

  test "accepts valid avatar attachment" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert @user.valid?
  end

  test "avatar_previewable? is false for unpersisted attachment" do
    @user.avatar.attach(
      io: StringIO.new("not an image"),
      filename: "avatar.txt",
      content_type: "text/plain"
    )
    assert_not @user.avatar_previewable?
  end

  test "avatar_previewable? is true for persisted image attachment" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert @user.avatar_previewable?
  end

  test "rejects avatar with invalid content type" do
    @user.avatar.attach(
      io: StringIO.new("not an image"),
      filename: "avatar.txt",
      content_type: "text/plain"
    )
    assert_not @user.valid?
    assert_includes @user.errors[:avatar], "must be a PNG, JPEG, WebP, or GIF image"
  end
end
