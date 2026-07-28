using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddQuestionnaire : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "questionnaire");

            migrationBuilder.CreateTable(
                name: "template",
                schema: "questionnaire",
                columns: table => new
                {
                    TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    Phase = table.Column<int>(type: "integer", nullable: false),
                    Version = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_template", x => x.TemplateId);
                });

            migrationBuilder.CreateTable(
                name: "response",
                schema: "questionnaire",
                columns: table => new
                {
                    ResponseId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    AssignedTo = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    SubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_response", x => x.ResponseId);
                    table.ForeignKey(
                        name: "FK_response_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_response_template_TemplateId",
                        column: x => x.TemplateId,
                        principalSchema: "questionnaire",
                        principalTable: "template",
                        principalColumn: "TemplateId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "section",
                schema: "questionnaire",
                columns: table => new
                {
                    SectionId = table.Column<Guid>(type: "uuid", nullable: false),
                    TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Title = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    Order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_section", x => x.SectionId);
                    table.ForeignKey(
                        name: "FK_section_template_TemplateId",
                        column: x => x.TemplateId,
                        principalSchema: "questionnaire",
                        principalTable: "template",
                        principalColumn: "TemplateId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "question",
                schema: "questionnaire",
                columns: table => new
                {
                    QuestionId = table.Column<Guid>(type: "uuid", nullable: false),
                    SectionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Text = table.Column<string>(type: "text", nullable: false),
                    HelpText = table.Column<string>(type: "text", nullable: true),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    IsRequired = table.Column<bool>(type: "boolean", nullable: false),
                    Order = table.Column<int>(type: "integer", nullable: false),
                    OptionsJson = table.Column<string>(type: "jsonb", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_question", x => x.QuestionId);
                    table.ForeignKey(
                        name: "FK_question_section_SectionId",
                        column: x => x.SectionId,
                        principalSchema: "questionnaire",
                        principalTable: "section",
                        principalColumn: "SectionId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "answer",
                schema: "questionnaire",
                columns: table => new
                {
                    AnswerId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResponseId = table.Column<Guid>(type: "uuid", nullable: false),
                    QuestionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Value = table.Column<string>(type: "text", nullable: true),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_answer", x => x.AnswerId);
                    table.ForeignKey(
                        name: "FK_answer_question_QuestionId",
                        column: x => x.QuestionId,
                        principalSchema: "questionnaire",
                        principalTable: "question",
                        principalColumn: "QuestionId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_answer_response_ResponseId",
                        column: x => x.ResponseId,
                        principalSchema: "questionnaire",
                        principalTable: "response",
                        principalColumn: "ResponseId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_answer_QuestionId",
                schema: "questionnaire",
                table: "answer",
                column: "QuestionId");

            migrationBuilder.CreateIndex(
                name: "IX_answer_ResponseId_QuestionId",
                schema: "questionnaire",
                table: "answer",
                columns: new[] { "ResponseId", "QuestionId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_question_SectionId",
                schema: "questionnaire",
                table: "question",
                column: "SectionId");

            migrationBuilder.CreateIndex(
                name: "IX_response_ProjectId_TemplateId",
                schema: "questionnaire",
                table: "response",
                columns: new[] { "ProjectId", "TemplateId" });

            migrationBuilder.CreateIndex(
                name: "IX_response_TemplateId",
                schema: "questionnaire",
                table: "response",
                column: "TemplateId");

            migrationBuilder.CreateIndex(
                name: "IX_section_TemplateId",
                schema: "questionnaire",
                table: "section",
                column: "TemplateId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "answer",
                schema: "questionnaire");

            migrationBuilder.DropTable(
                name: "question",
                schema: "questionnaire");

            migrationBuilder.DropTable(
                name: "response",
                schema: "questionnaire");

            migrationBuilder.DropTable(
                name: "section",
                schema: "questionnaire");

            migrationBuilder.DropTable(
                name: "template",
                schema: "questionnaire");
        }
    }
}
