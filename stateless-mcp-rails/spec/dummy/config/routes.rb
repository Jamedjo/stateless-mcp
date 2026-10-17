Rails.application.routes.draw do
  mcp_server module: "mcp" do
    mcp_resource :notes, only: [:index, :show] do
      mcp_member :body
    end
  end

  mcp_server Dummy::ADMIN_MCP, module: "admin" do
    mcp_resource :notes, only: [:index]
    mcp_tool "count_notes", to: "notes#count"
  end
end
