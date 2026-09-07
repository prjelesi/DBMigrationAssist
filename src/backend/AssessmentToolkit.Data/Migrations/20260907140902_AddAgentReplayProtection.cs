using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAgentReplayProtection : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_assessment_result_JobId",
                schema: "assessment",
                table: "assessment_result");

            migrationBuilder.CreateTable(
                name: "agent_request_nonce",
                schema: "assessment",
                columns: table => new
                {
                    AgentId = table.Column<Guid>(type: "uuid", nullable: false),
                    Nonce = table.Column<Guid>(type: "uuid", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_agent_request_nonce", x => new { x.AgentId, x.Nonce });
                    table.ForeignKey(
                        name: "FK_agent_request_nonce_agent_AgentId",
                        column: x => x.AgentId,
                        principalSchema: "assessment",
                        principalTable: "agent",
                        principalColumn: "AgentId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.Sql(
                """
                DELETE FROM assessment.assessment_result
                WHERE "ResultId" IN (
                    SELECT "ResultId"
                    FROM (
                        SELECT
                            "ResultId",
                            ROW_NUMBER() OVER (
                                PARTITION BY "JobId"
                                ORDER BY "CreatedAt", "ResultId") AS row_number
                        FROM assessment.assessment_result
                    ) AS duplicate_results
                    WHERE row_number > 1
                );
                """);

            migrationBuilder.CreateIndex(
                name: "IX_assessment_result_JobId",
                schema: "assessment",
                table: "assessment_result",
                column: "JobId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_agent_request_nonce_ExpiresAt",
                schema: "assessment",
                table: "agent_request_nonce",
                column: "ExpiresAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "agent_request_nonce",
                schema: "assessment");

            migrationBuilder.DropIndex(
                name: "IX_assessment_result_JobId",
                schema: "assessment",
                table: "assessment_result");

            migrationBuilder.CreateIndex(
                name: "IX_assessment_result_JobId",
                schema: "assessment",
                table: "assessment_result",
                column: "JobId");
        }
    }
}
