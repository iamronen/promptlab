class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :projects, dependent: :restrict_with_error
  has_many :created_sequences, class_name: "Sequence", foreign_key: :created_by_id,
                               inverse_of: :created_by, dependent: :restrict_with_error

  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  AVATAR_MAX_SIZE = 5.megabytes
  DISPLAY_NAME_MAX_LENGTH = 100

  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 64, 64 ]
  end

  validates :display_name, length: { maximum: DISPLAY_NAME_MAX_LENGTH }, allow_blank: true
  validate :avatar_content_type_and_size, if: -> { avatar.attached? }

  before_validation :strip_display_name

  def display_label
    display_name.presence || email
  end

  def avatar_previewable?
    avatar.attached? &&
      avatar.blob.persisted? &&
      avatar.blob.content_type.to_s.start_with?("image/")
  end

  private

  def strip_display_name
    self.display_name = display_name&.strip
    self.display_name = nil if display_name.blank?
  end

  def avatar_content_type_and_size
    unless AVATAR_CONTENT_TYPES.include?(avatar.blob.content_type)
      errors.add(:avatar, "must be a PNG, JPEG, WebP, or GIF image")
    end

    if avatar.blob.byte_size > AVATAR_MAX_SIZE
      errors.add(:avatar, "must be smaller than #{AVATAR_MAX_SIZE / 1.megabyte} MB")
    end
  end
end
