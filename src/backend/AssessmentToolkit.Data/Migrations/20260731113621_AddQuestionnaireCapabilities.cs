using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddQuestionnaireCapabilities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "QuestionId",
                schema: "assessment",
                table: "uploaded_report",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "QuestionnaireResponseId",
                schema: "assessment",
                table: "uploaded_report",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AllowAttachments",
                schema: "questionnaire",
                table: "question",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "AllowCustomAnswer",
                schema: "questionnaire",
                table: "question",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateIndex(
                name: "IX_uploaded_report_QuestionId",
                schema: "assessment",
                table: "uploaded_report",
                column: "QuestionId");

            migrationBuilder.CreateIndex(
                name: "IX_uploaded_report_QuestionnaireResponseId_QuestionId",
                schema: "assessment",
                table: "uploaded_report",
                columns: new[] { "QuestionnaireResponseId", "QuestionId" });

            migrationBuilder.AddForeignKey(
                name: "FK_uploaded_report_question_QuestionId",
                schema: "assessment",
                table: "uploaded_report",
                column: "QuestionId",
                principalSchema: "questionnaire",
                principalTable: "question",
                principalColumn: "QuestionId",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_uploaded_report_response_QuestionnaireResponseId",
                schema: "assessment",
                table: "uploaded_report",
                column: "QuestionnaireResponseId",
                principalSchema: "questionnaire",
                principalTable: "response",
                principalColumn: "ResponseId",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_uploaded_report_question_QuestionId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropForeignKey(
                name: "FK_uploaded_report_response_QuestionnaireResponseId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropIndex(
                name: "IX_uploaded_report_QuestionId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropIndex(
                name: "IX_uploaded_report_QuestionnaireResponseId_QuestionId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropColumn(
                name: "QuestionId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropColumn(
                name: "QuestionnaireResponseId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropColumn(
                name: "AllowAttachments",
                schema: "questionnaire",
                table: "question");

            migrationBuilder.DropColumn(
                name: "AllowCustomAnswer",
                schema: "questionnaire",
                table: "question");
        }
    }
}
