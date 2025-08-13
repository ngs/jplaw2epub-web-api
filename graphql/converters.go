package graphql

import (
	jplaw "go.ngs.io/jplaw-api-v2"
	"go.ngs.io/jplaw2epub-web-api/graphql/model"
)

var categoryCodeMap = map[model.CategoryCode]jplaw.CategoryCd{
	model.CategoryCodeConstitution:         jplaw.CategoryCdConstitution,
	model.CategoryCodeCriminal:             jplaw.CategoryCdCriminal,
	model.CategoryCodeFinanceGeneral:       jplaw.CategoryCdFinanceGeneral,
	model.CategoryCodeFisheries:            jplaw.CategoryCdFisheries,
	model.CategoryCodeTourism:              jplaw.CategoryCdTourism,
	model.CategoryCodeParliament:           jplaw.CategoryCdParliament,
	model.CategoryCodePolice:               jplaw.CategoryCdPolice,
	model.CategoryCodeNationalProperty:     jplaw.CategoryCdNationalProperty,
	model.CategoryCodeMining:               jplaw.CategoryCdMining,
	model.CategoryCodePostalService:        jplaw.CategoryCdPostalService,
	model.CategoryCodeAdministrativeOrg:    jplaw.CategoryCdAdministrativeOrg,
	model.CategoryCodeFireService:          jplaw.CategoryCdFireService,
	model.CategoryCodeNationalTax:          jplaw.CategoryCdNationalTax,
	model.CategoryCodeIndustry:             jplaw.CategoryCdIndustry,
	model.CategoryCodeTelecommunications:   jplaw.CategoryCdTelecommunications,
	model.CategoryCodeCivilService:         jplaw.CategoryCdCivilService,
	model.CategoryCodeNationalDevelopment:  jplaw.CategoryCdNationalDevelopment,
	model.CategoryCodeBusiness:             jplaw.CategoryCdBusiness,
	model.CategoryCodeCommerce:             jplaw.CategoryCdCommerce,
	model.CategoryCodeLabor:                jplaw.CategoryCdLabor,
	model.CategoryCodeAdministrativeProc:   jplaw.CategoryCdAdministrativeProc,
	model.CategoryCodeLand:                 jplaw.CategoryCdLand,
	model.CategoryCodeNationalBonds:        jplaw.CategoryCdNationalBonds,
	model.CategoryCodeFinanceInsurance:     jplaw.CategoryCdFinanceInsurance,
	model.CategoryCodeEnvironmentalProtect: jplaw.CategoryCdEnvironmentalProtect,
	model.CategoryCodeStatistics:           jplaw.CategoryCdStatistics,
	model.CategoryCodeCityPlanning:         jplaw.CategoryCdCityPlanning,
	model.CategoryCodeEducation:            jplaw.CategoryCdEducation,
	model.CategoryCodeForeignExchangeTrade: jplaw.CategoryCdForeignExchangeTrade,
	model.CategoryCodePublicHealth:         jplaw.CategoryCdPublicHealth,
	model.CategoryCodeLocalGovernment:      jplaw.CategoryCdLocalGovernment,
	model.CategoryCodeRoads:                jplaw.CategoryCdRoads,
	model.CategoryCodeCulture:              jplaw.CategoryCdCulture,
	model.CategoryCodeLandTransport:        jplaw.CategoryCdLandTransport,
	model.CategoryCodeSocialWelfare:        jplaw.CategoryCdSocialWelfare,
	model.CategoryCodeLocalFinance:         jplaw.CategoryCdLocalFinance,
	model.CategoryCodeRivers:               jplaw.CategoryCdRivers,
	model.CategoryCodeIndustryGeneral:      jplaw.CategoryCdIndustryGeneral,
	model.CategoryCodeMaritimeTransport:    jplaw.CategoryCdMaritimeTransport,
	model.CategoryCodeSocialInsurance:      jplaw.CategoryCdSocialInsurance,
	model.CategoryCodeJudiciary:            jplaw.CategoryCdJudiciary,
	model.CategoryCodeDisasterManagement:   jplaw.CategoryCdDisasterManagement,
	model.CategoryCodeAgriculture:          jplaw.CategoryCdAgriculture,
	model.CategoryCodeAviation:             jplaw.CategoryCdAviation,
	model.CategoryCodeDefense:              jplaw.CategoryCdDefense,
	model.CategoryCodeCivil:                jplaw.CategoryCdCivil,
	model.CategoryCodeBuildingHousing:      jplaw.CategoryCdBuildingHousing,
	model.CategoryCodeForestry:             jplaw.CategoryCdForestry,
	model.CategoryCodeFreightTransport:     jplaw.CategoryCdFreightTransport,
	model.CategoryCodeForeignAffairs:       jplaw.CategoryCdForeignAffairs,
}

// convertCategoryCode converts GraphQL CategoryCode to jplaw CategoryCd
func convertCategoryCode(codes []model.CategoryCode) []jplaw.CategoryCd {
	if len(codes) == 0 {
		return nil
	}

	result := make([]jplaw.CategoryCd, 0, len(codes))
	for _, code := range codes {
		if mapped, ok := categoryCodeMap[code]; ok {
			result = append(result, mapped)
		}
	}
	return result
}

// convertLawType converts GraphQL LawType to jplaw LawType
func convertLawType(types []model.LawType) []jplaw.LawType {
	if len(types) == 0 {
		return nil
	}

	result := make([]jplaw.LawType, 0, len(types))
	for _, t := range types {
		switch t {
		case model.LawTypeConstitution:
			result = append(result, jplaw.LawTypeConstitution)
		case model.LawTypeAct:
			result = append(result, jplaw.LawTypeAct)
		case model.LawTypeCabinetOrder:
			result = append(result, jplaw.LawTypeCabinetorder)
		case model.LawTypeImperialOrder:
			result = append(result, jplaw.LawTypeImperialorder)
		case model.LawTypeMinisterialOrdinance:
			result = append(result, jplaw.LawTypeMinisterialordinance)
		case model.LawTypeRule:
			result = append(result, jplaw.LawTypeRule)
		case model.LawTypeMisc:
			result = append(result, jplaw.LawTypeMisc)
		}
	}
	return result
}

// Reverse conversions for output

func convertLawTypeToModel(t *jplaw.LawType) *model.LawType {
	if t == nil {
		return nil
	}

	var result model.LawType
	switch *t {
	case jplaw.LawTypeConstitution:
		result = model.LawTypeConstitution
	case jplaw.LawTypeAct:
		result = model.LawTypeAct
	case jplaw.LawTypeCabinetorder:
		result = model.LawTypeCabinetOrder
	case jplaw.LawTypeImperialorder:
		result = model.LawTypeImperialOrder
	case jplaw.LawTypeMinisterialordinance:
		result = model.LawTypeMinisterialOrdinance
	case jplaw.LawTypeRule:
		result = model.LawTypeRule
	case jplaw.LawTypeMisc:
		result = model.LawTypeMisc
	default:
		return nil
	}
	return &result
}

func convertLawNumEraToModel(e *jplaw.LawNumEra) *model.LawNumEra {
	if e == nil {
		return nil
	}

	var result model.LawNumEra
	switch *e {
	case jplaw.LawNumEraMeiji:
		result = model.LawNumEraMeiji
	case jplaw.LawNumEraTaisho:
		result = model.LawNumEraTaisho
	case jplaw.LawNumEraShowa:
		result = model.LawNumEraShowa
	case jplaw.LawNumEraHeisei:
		result = model.LawNumEraHeisei
	case jplaw.LawNumEraReiwa:
		result = model.LawNumEraReiwa
	default:
		return nil
	}
	return &result
}

func convertLawNumTypeToModel(t *jplaw.LawNumType) *model.LawNumType {
	if t == nil {
		return nil
	}

	var result model.LawNumType
	switch *t {
	case jplaw.LawNumTypeConstitution:
		result = model.LawNumTypeConstitution
	case jplaw.LawNumTypeAct:
		result = model.LawNumTypeAct
	case jplaw.LawNumTypeCabinetorder:
		result = model.LawNumTypeCabinetOrder
	case jplaw.LawNumTypeImperialorder:
		result = model.LawNumTypeImperialOrder
	case jplaw.LawNumTypeMinisterialordinance:
		result = model.LawNumTypeMinisterialOrdinance
	case jplaw.LawNumTypeRule:
		result = model.LawNumTypeRule
	case jplaw.LawNumTypeMisc:
		result = model.LawNumTypeMisc
	default:
		return nil
	}
	return &result
}

func convertCurrentRevisionStatusToModel(s *jplaw.CurrentRevisionStatus) *model.CurrentRevisionStatus {
	if s == nil {
		return nil
	}

	var result model.CurrentRevisionStatus
	switch *s {
	case jplaw.CurrentRevisionStatusCurrentenforced:
		result = model.CurrentRevisionStatusCurrentEnforced
	case jplaw.CurrentRevisionStatusUnenforced:
		result = model.CurrentRevisionStatusUnenforced
	case jplaw.CurrentRevisionStatusPreviousenforced:
		result = model.CurrentRevisionStatusPreviousEnforced
	case jplaw.CurrentRevisionStatusRepeal:
		result = model.CurrentRevisionStatusRepeal
	default:
		return nil
	}
	return &result
}

func convertRepealStatusToModel(s *jplaw.RepealStatus) *model.RepealStatus {
	if s == nil {
		return nil
	}

	var result model.RepealStatus
	switch *s {
	case jplaw.RepealStatusNone:
		result = model.RepealStatusNone
	case jplaw.RepealStatusRepeal:
		result = model.RepealStatusRepeal
	case jplaw.RepealStatusExpire:
		result = model.RepealStatusExpire
	case jplaw.RepealStatusSuspend:
		result = model.RepealStatusSuspend
	case jplaw.RepealStatusLossofeffectiveness:
		result = model.RepealStatusLossOfEffectiveness
	default:
		return nil
	}
	return &result
}

func convertMissionToModel(m *jplaw.Mission) *model.Mission {
	if m == nil {
		return nil
	}

	var result model.Mission
	switch *m {
	case jplaw.MissionNew:
		result = model.MissionNew
	case jplaw.MissionPartial:
		result = model.MissionPartial
	default:
		return nil
	}
	return &result
}
