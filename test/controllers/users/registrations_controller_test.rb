# frozen_string_literal: true

require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    sign_in @user
  end

  test "edit shows account settings tool inside application shell" do
    get edit_user_registration_path
    assert_response :success
    assert_select ".application-shell"
    assert_select ".tool-container--centered"
    assert_select ".tool-heading-title", text: "Account Settings"
    assert_select "input[name='user[display_name]']"
    assert_select "input[name='user[avatar]'][type='file']"
  end

  test "update saves display name" do
    patch user_registration_path, params: {
      user: {
        display_name: "Alice Example",
        current_password: "password123"
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_equal "Alice Example", @user.reload.display_name
  end

  test "update attaches avatar" do
    patch user_registration_path, params: {
      user: {
        avatar: fixture_file_upload("avatar.png", "image/png"),
        current_password: "password123"
      }
    }

    assert_redirected_to edit_user_registration_path
    assert @user.reload.avatar.attached?
  end

  test "update removes avatar when remove_avatar is checked" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )

    patch user_registration_path, params: {
      user: {
        remove_avatar: "1",
        current_password: "password123"
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_not @user.reload.avatar.attached?
  end

  test "update with wrong password re-renders edit when avatar uploaded" do
    patch user_registration_path, params: {
      user: {
        avatar: fixture_file_upload("avatar.png", "image/png"),
        current_password: "wrong-password"
      }
    }

    assert_response :unprocessable_content
    assert_select ".tool-heading-title", text: "Account Settings"
    assert_not @user.reload.avatar.attached?
  end

  test "update rejects invalid avatar content type" do
    patch user_registration_path, params: {
      user: {
        avatar: fixture_file_upload("not_an_image.txt", "text/plain"),
        current_password: "password123"
      }
    }

    assert_response :unprocessable_content
    assert_not @user.reload.avatar.attached?
  end
end
