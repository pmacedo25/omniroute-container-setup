"""Single-provider model catalogue for the OmniRoute OpenHands appliance."""

from typing import AsyncGenerator

from fastapi import Request

from openhands.app_server.config_api.config_models import (
    LLMModel,
    LLMModelPage,
    Provider,
    ProviderPage,
)
from openhands.app_server.config_api.llm_model_service import (
    LLMModelService,
    LLMModelServiceInjector,
)
from openhands.app_server.services.injector import InjectorState


_MODELS = (
    LLMModel(provider="omniroute", name="openai/combo-coding", verified=True),
    LLMModel(provider="omniroute", name="openai/combo-refining", verified=True),
    LLMModel(provider="omniroute", name="openai/combo-testing", verified=True),
)


class DefaultLLMModelService(LLMModelService):
    """Expose only the locally managed OmniRoute models."""

    def __init__(self, **_: object) -> None:
        pass

    async def search_llm_models(
        self,
        *,
        query: str | None = None,
        verified_eq: bool | None = None,
        provider_eq: str | None = None,
        page_id: str | None = None,
        limit: int = 50,
    ) -> LLMModelPage:
        models = list(_MODELS)
        if provider_eq is not None:
            models = [model for model in models if model.provider == provider_eq]
        if query is not None:
            query_lower = query.lower()
            models = [model for model in models if query_lower in model.name.lower()]
        if verified_eq is not None:
            models = [model for model in models if model.verified == verified_eq]
        return LLMModelPage(items=models[:limit], next_page_id=None)

    async def search_providers(
        self,
        *,
        query: str | None = None,
        verified_eq: bool | None = None,
        page_id: str | None = None,
        limit: int = 50,
    ) -> ProviderPage:
        provider = Provider(name="omniroute", verified=True)
        providers = [provider]
        if query is not None and query.lower() not in provider.name.lower():
            providers = []
        if verified_eq is False:
            providers = []
        return ProviderPage(items=providers[:limit], next_page_id=None)


class DefaultLLMModelServiceInjector(LLMModelServiceInjector):
    """Inject the restricted catalogue for every request."""

    aws_region_name: str | None = None
    aws_access_key_id: object | None = None
    aws_secret_access_key: object | None = None
    ollama_base_url: str | None = None

    async def inject(
        self, state: InjectorState, request: Request | None = None
    ) -> AsyncGenerator[LLMModelService, None]:
        yield DefaultLLMModelService()
