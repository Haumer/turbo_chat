module ChatGem
  class ChatsController < ApplicationController
    module EventPayloadSupport
      private

      def invitation_accepted_payload
        payload = flash[:chat_gem_invitation_accepted]
        return nil unless payload.respond_to?(:to_h)

        symbolized_payload = payload.to_h.symbolize_keys
        chat_id = symbolized_payload[:chatId].presence || symbolized_payload[:chat_id].presence
        return nil if chat_id.blank?

        {
          chatId: chat_id.to_s,
          chatTitle: symbolized_payload[:chatTitle].presence || symbolized_payload[:chat_title].presence,
          chatMembershipId: symbolized_payload[:chatMembershipId].presence || symbolized_payload[:chat_membership_id].presence
        }.compact
      rescue StandardError
        nil
      end

      def chat_lifecycle_event_payload
        payload = flash[:chat_gem_chat_lifecycle_event]
        return nil unless payload.respond_to?(:to_h)

        symbolized_payload = payload.to_h.symbolize_keys
        event_name = symbolized_payload[:eventName].presence || symbolized_payload[:event_name].presence
        return nil if event_name.blank?

        chat_id = symbolized_payload[:chatId].presence || symbolized_payload[:chat_id].presence

        {
          eventName: event_name.to_s,
          action: symbolized_payload[:action].presence,
          chatId: chat_id.to_s.presence,
          chatTitle: symbolized_payload[:chatTitle].presence || symbolized_payload[:chat_title].presence,
          chatMembershipId: symbolized_payload[:chatMembershipId].presence || symbolized_payload[:chat_membership_id].presence
        }.compact
      rescue StandardError
        nil
      end

      def set_chat_lifecycle_event(action:, chat:, membership: nil)
        return if action.blank? || chat.nil?

        action_key = action.to_s
        flash[:chat_gem_chat_lifecycle_event] = {
          eventName: "chat-gem:chat-#{action_key}",
          action: action_key,
          chatId: chat.id.to_s,
          chatTitle: chat.title,
          chatMembershipId: membership&.id&.to_s
        }.compact
      end
    end
  end
end
