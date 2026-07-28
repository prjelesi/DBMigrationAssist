using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddGraphEdge : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "graph");

            migrationBuilder.CreateTable(
                name: "edge",
                schema: "graph",
                columns: table => new
                {
                    EdgeId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    SourceDatabaseId = table.Column<Guid>(type: "uuid", nullable: false),
                    TargetDatabaseId = table.Column<Guid>(type: "uuid", nullable: false),
                    RelationType = table.Column<string>(type: "text", nullable: false),
                    Protocol = table.Column<string>(type: "text", nullable: false),
                    Direction = table.Column<string>(type: "text", nullable: false),
                    Confidence = table.Column<string>(type: "text", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_edge", x => x.EdgeId);
                    table.ForeignKey(
                        name: "FK_edge_database_instance_SourceDatabaseId",
                        column: x => x.SourceDatabaseId,
                        principalSchema: "inventory",
                        principalTable: "database_instance",
                        principalColumn: "DatabaseId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_edge_database_instance_TargetDatabaseId",
                        column: x => x.TargetDatabaseId,
                        principalSchema: "inventory",
                        principalTable: "database_instance",
                        principalColumn: "DatabaseId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_edge_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_edge_ProjectId",
                schema: "graph",
                table: "edge",
                column: "ProjectId");

            migrationBuilder.CreateIndex(
                name: "IX_edge_SourceDatabaseId",
                schema: "graph",
                table: "edge",
                column: "SourceDatabaseId");

            migrationBuilder.CreateIndex(
                name: "IX_edge_TargetDatabaseId",
                schema: "graph",
                table: "edge",
                column: "TargetDatabaseId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "edge",
                schema: "graph");
        }
    }
}
