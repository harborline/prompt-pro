import { AIExtension, getDefaultAIMenuItems } from "@blocknote/xl-ai";
import {
  RiBallPenLine,
  RiListCheck3,
  RiMagicLine,
  RiRobot2Line,
  RiScissorsCutLine
} from "react-icons/ri";

export function getPromptProducerAIMenuItems(
  editor,
  aiResponseStatus,
  currentConfig = {},
  runNativeAIEdit
) {
  if (aiResponseStatus !== "user-input") {
    return getDefaultAIMenuItems(editor, aiResponseStatus);
  }

  const ai = editor.getExtension(AIExtension);
  if (!ai && typeof runNativeAIEdit !== "function") {
    return [];
  }

  const modelName = currentConfig.model?.trim();
  const invokeAI = async (userPrompt) => {
    if (typeof runNativeAIEdit === "function") {
      await runNativeAIEdit(userPrompt);
      ai?.closeAIMenu?.();
      return;
    }

    await ai.invokeAI({ userPrompt, useSelection: editor.getSelection() !== undefined });
  };

  return [
    {
      key: "write_prompt_about",
      title: "Write a prompt about",
      aliases: ["write", "prompt", "topic"],
      icon: <RiBallPenLine size={18} />,
      onItemClick: (setPrompt) => {
        setPrompt("Write a prompt about ");
      },
      size: "small"
    },
    {
      key: "elaborate",
      title: "Elaborate",
      aliases: ["expand", "detail", "develop"],
      icon: <RiMagicLine size={18} />,
      onItemClick: async () => {
        await invokeAI(
          "Elaborate this prompt with useful context, constraints, examples, and success criteria."
        );
      },
      size: "small"
    },
    {
      key: "make_more_concise",
      title: "Make more concise",
      aliases: ["shorten", "concise", "trim"],
      icon: <RiScissorsCutLine size={18} />,
      onItemClick: async () => {
        await invokeAI(
          "Make this prompt more concise while preserving the intent, constraints, and output requirements."
        );
      },
      size: "small"
    },
    {
      key: "add_action_items",
      title: "Add Action Items",
      aliases: ["tasks", "actions", "checklist"],
      icon: <RiListCheck3 size={18} />,
      onItemClick: async () => {
        await invokeAI("Add clear action items to this prompt.");
      },
      size: "small"
    },
    {
      key: "tailor_to_specific_ai_model",
      title: "Tailor to this specific AI model:",
      aliases: ["model", "tailor", "optimize"],
      icon: <RiRobot2Line size={18} />,
      onItemClick: (setPrompt) => {
        setPrompt(
          modelName
            ? `Tailor this prompt to work best with ${modelName}: `
            : "Tailor this prompt to this specific AI model: "
        );
      },
      size: "small"
    }
  ];
}
