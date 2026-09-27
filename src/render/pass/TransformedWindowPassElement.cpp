#include "TransformedWindowPassElement.hpp"

CTransformedWindowPassElement::CTransformedWindowPassElement(CTransformedWindowPassElement::SData&& data) : m_data(std::move(data)) {
    ;
}

bool CTransformedWindowPassElement::needsLiveBlur() {
    return (m_data.blur && m_data.blurUsesLive) || (m_data.pass && m_data.pass->needsLiveBlur());
}

bool CTransformedWindowPassElement::needsPrecomputeBlur() {
    return (m_data.blur && !m_data.blurUsesLive) || (m_data.pass && m_data.pass->needsPrecomputeBlur());
}

std::optional<CBox> CTransformedWindowPassElement::boundingBox() {
    return m_data.transformedBox.empty() ? m_data.currentBox : m_data.transformedBox;
}

CRegion CTransformedWindowPassElement::opaqueRegion() {
    return {};
}

bool CTransformedWindowPassElement::disableSimplification() {
    return true;
}
